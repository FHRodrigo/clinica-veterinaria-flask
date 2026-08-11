import pyodbc
from flask import Flask, render_template, request, redirect, url_for, session

app = Flask(__name__)
app.secret_key = 'clave_secreta_clinica_veterinaria' # Necesario para usar session de forma segura

# Configuración de tu conexión a SQL Server
DB_CONFIG = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    r"SERVER=DESKTOP-SSIPS8T\SQLEXPRESS;"
    "DATABASE=ClinicaVeterinaria_DB1;"
    "Trusted_Connection=yes;"
)

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/recepcion')
def recepcion():
    return render_template('recepcion_panel.html')

@app.route('/recepcion/dueno', methods=['GET', 'POST'])
def registrar_dueno():
    mensaje = None
    if request.method == 'POST':
        try:
            nombre = request.form['nombre']
            email = request.form['email']
            telefono = request.form['telefono']
            direccion = request.form['direccion']
            tipo_doc = request.form['tipo_doc']
            num_doc_plano = request.form['num_doc']
            
            conn = pyodbc.connect(DB_CONFIG)
            cursor = conn.cursor()
            cursor.execute(
                "EXEC sp_RegistrarDueno ?, ?, ?, ?, ?, ?",
                (nombre, email, telefono, direccion, tipo_doc, num_doc_plano)
            )
            conn.commit()
            cursor.close()
            conn.close()
            
            mensaje = "¡Dueño registrado con éxito!"
        except Exception as e:
            mensaje = f"Error (Atrapado por TRY/CATCH de la BD o validación): {e}"
    return render_template('registrar_dueno.html', mensaje=mensaje)

@app.route('/recepcion/mascota', methods=['GET', 'POST'])
def registrar_mascota():
    mensaje = None
    duenos = []
    try:
        conn = pyodbc.connect(DB_CONFIG)
        cursor = conn.cursor()
        
        if request.method == 'POST':
            dueno_id = request.form['dueno_id']
            nombre = request.form['nombre']
            especie = request.form['especie']
            raza = request.form['raza']
            edad = request.form['edad'] if request.form['edad'] else None
            peso = request.form['peso'] if request.form['peso'] else None
            
            cursor.execute(
                "INSERT INTO Mascotas (nombre, especie, raza, edad, peso, dueno_id) VALUES (?, ?, ?, ?, ?, ?)",
                (nombre, especie, raza, edad, peso, dueno_id)
            )
            conn.commit()
            mensaje = "¡Mascota registrada exitosamente!"
                
        cursor.execute("SELECT dueno_id, nombre_completo FROM Duenos")
        duenos = cursor.fetchall()
        cursor.close()
        conn.close()
    except Exception as e:
        mensaje = f"Error al cargar la vista: {e}"

    return render_template('registrar_mascota.html', duenos=duenos, mensaje=mensaje)

@app.route('/recepcion/consulta', methods=['GET', 'POST'])
def registrar_consulta():
    mensaje = None
    conn = pyodbc.connect(DB_CONFIG)
    cursor = conn.cursor()
    
    if request.method == 'POST':
        mascota_id = request.form['mascota_id']
        veterinario_id = request.form['veterinario_id']
        motivo = request.form['motivo']
        try:
            cursor.execute("EXEC sp_RegistrarConsulta ?, ?, ?", (mascota_id, veterinario_id, motivo))
            conn.commit()
            mensaje = "¡Consulta programada exitosamente con estado 'Programada'!"
        except Exception as e:
            mensaje = f"Error al programar consulta: {e}"
            
    cursor.execute("SELECT mascota_id, nombre, especie FROM Mascotas")
    mascotas = cursor.fetchall()
    cursor.execute("SELECT veterinario_id, nombre_completo, especialidad FROM Veterinarios WHERE estado = 'Activo'")
    veterinarios = cursor.fetchall()
    cursor.close()
    conn.close()
    return render_template('registrar_consulta.html', mascotas=mascotas, veterinarios=veterinarios, mensaje=mensaje)

@app.route('/recepcion/factura', methods=['GET', 'POST'])
def registrar_factura():
    mensaje = None
    conn = pyodbc.connect(DB_CONFIG)
    cursor = conn.cursor()
    
    if request.method == 'POST':
        consulta_id = request.form['consulta_id']
        total = request.form['total']
        metodo_pago = request.form['metodo_pago']
        referencia_pago = request.form['referencia_pago']
        try:
            cursor.execute("EXEC sp_RegistrarFactura ?, ?, ?, ?", (consulta_id, total, metodo_pago, referencia_pago))
            conn.commit()
            mensaje = "¡Factura generada con éxito (folio asignado por secuencia y referencia cifrada)!"
        except Exception as e:
            mensaje = f"Error al generar factura: {e}"
            
    cursor.execute("SELECT consulta_id, motivo FROM Consultas")
    consultas = cursor.fetchall()
    cursor.close()
    conn.close()
    return render_template('registrar_factura.html', consultas=consultas, mensaje=mensaje)

# --- RUTAS DE LOGIN Y SESIÓN PARA ADMINISTRADOR ---

@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        usuario = request.form.get('usuario')
        contrasena = request.form.get('contrasena')
        
        if usuario == 'admin' and contrasena == 'admin123':
            session['admin_logueado'] = True
            return redirect(url_for('administrador'))
        else:
            error = 'Usuario o contraseña incorrectos. Intenta nuevamente.'
            
    return render_template('login.html', error=error)

@app.route('/logout')
def logout():
    session.pop('admin_logueado', None)
    return redirect(url_for('login'))

# --- RUTA PROTEGIDA DEL PANEL DE ADMINISTRADOR ---

@app.route('/administrador')
def administrador():
    if not session.get('admin_logueado'):
        return redirect(url_for('login'))

    clientes = []
    veterinarios = []
    lista_duenos = []
    lista_mascotas = []
    
    try:
        conn = pyodbc.connect(DB_CONFIG)
        cursor = conn.cursor()
        
        # 1. Consulta avanzada: Clasificación de Lealtad (JOINs y CASE)
        cursor.execute("""
            SELECT 
                d.dueno_id,
                d.nombre_completo AS Dueno,
                COUNT(c.consulta_id) AS Total_Consultas,
                CASE 
                    WHEN COUNT(c.consulta_id) >= 5 THEN 'Cliente VIP'
                    WHEN COUNT(c.consulta_id) BETWEEN 2 AND 4 THEN 'Cliente Frecuente'
                    ELSE 'Cliente Ocasional'
                END AS Clasificacion_Lealtad
            FROM Duenos d
            LEFT JOIN Mascotas m ON d.dueno_id = m.dueno_id
            LEFT JOIN Consultas c ON m.mascota_id = c.mascota_id
            GROUP BY d.dueno_id, d.nombre_completo
            ORDER BY Total_Consultas DESC;
        """)
        clientes = cursor.fetchall()
        
        # 2. Consulta avanzada: Ranking de Veterinarios (Incluyendo ID para los enlaces)
        cursor.execute("""
            SELECT 
                v.veterinario_id,
                v.nombre_completo AS Veterinario,
                v.especialidad,
                COUNT(c.consulta_id) AS Consultas_Atendidas,
                RANK() OVER (ORDER BY COUNT(c.consulta_id) DESC) AS Ranking_Productividad
            FROM Veterinarios v
            LEFT JOIN Consultas c ON v.veterinario_id = c.veterinario_id
            GROUP BY v.veterinario_id, v.nombre_completo, v.especialidad;
        """)
        veterinarios = cursor.fetchall()

        # 3. Listados completos para los enlaces de detalles en el panel
        cursor.execute("SELECT dueno_id, nombre_completo FROM Duenos")
        lista_duenos = cursor.fetchall()

        cursor.execute("SELECT mascota_id, nombre, especie FROM Mascotas")
        lista_mascotas = cursor.fetchall()
        
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"Error al cargar reportes de administrador: {e}")

    return render_template('administrador_panel.html', 
                           clientes=clientes, 
                           veterinarios=veterinarios, 
                           lista_duenos=lista_duenos, 
                           lista_mascotas=lista_mascotas)

# --- RUTAS DE DETALLES (MAESTRO-DETALLE) ---

@app.route('/detalles/dueno/<int:id>')
def detalle_dueno(id):
    if not session.get('admin_logueado'): return redirect(url_for('login'))
    conn = pyodbc.connect(DB_CONFIG)
    cursor = conn.cursor()
    
    cursor.execute("SELECT nombre_completo, email, telefono, direccion, tipo_documento, fecha_registro FROM Duenos WHERE dueno_id = ?", (id,))
    datos = cursor.fetchone()
    
    cursor.execute("SELECT nombre, especie, raza FROM Mascotas WHERE dueno_id = ?", (id,))
    mascotas = cursor.fetchall()
    
    cursor.close()
    conn.close()
    return render_template('detalle.html', tipo='Dueño', datos=datos, extras=mascotas, titulo_extra='Mascotas Asociadas')

@app.route('/detalles/mascota/<int:id>')
def detalle_mascota(id):
    if not session.get('admin_logueado'): return redirect(url_for('login'))
    conn = pyodbc.connect(DB_CONFIG)
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT m.nombre, m.especie, m.raza, m.edad, m.peso, d.nombre_completo 
        FROM Mascotas m 
        JOIN Duenos d ON m.dueno_id = d.dueno_id 
        WHERE m.mascota_id = ?""", (id,))
    datos = cursor.fetchone()
    
    cursor.close()
    conn.close()
    return render_template('detalle.html', tipo='Mascota', datos=datos)

@app.route('/detalles/veterinario/<int:id>')
def detalle_veterinario(id):
    if not session.get('admin_logueado'): return redirect(url_for('login'))
    conn = pyodbc.connect(DB_CONFIG)
    cursor = conn.cursor()
    
    cursor.execute("SELECT nombre_completo, especialidad, usuario, estado FROM Veterinarios WHERE veterinario_id = ?", (id,))
    datos = cursor.fetchone()
    
    cursor.execute("""
        SELECT c.consulta_id, m.nombre, m.especie, c.fecha_consulta, c.motivo, c.estado 
        FROM Consultas c
        JOIN Mascotas m ON c.mascota_id = m.mascota_id
        WHERE c.veterinario_id = ?
    """, (id,))
    consultas = cursor.fetchall()
    
    cursor.close()
    conn.close()
    # Pasamos veterinario_id a la plantilla
    return render_template('detalle_veterinario.html', datos=datos, consultas=consultas, veterinario_id=id)
@app.route('/veterinario/toggle/<int:id>', methods=['POST'])
def toggle_veterinario(id):
    if not session.get('admin_logueado'):
        return redirect(url_for('login'))
        
    try:
        conn = pyodbc.connect(DB_CONFIG)
        cursor = conn.cursor()
        # Alterna el estado actual de forma automática
        cursor.execute("""
            UPDATE Veterinarios 
            SET estado = CASE WHEN estado = 'Activo' THEN 'Inactivo' ELSE 'Activo' END 
            WHERE veterinario_id = ?
        """, (id,))
        conn.commit()
        cursor.close()
        conn.close()
    except Exception as e:
        print(f"Error al cambiar el estado del veterinario: {e}")
        
    # Redirige de regreso a los detalles de ese veterinario
    return redirect(url_for('detalle_veterinario', id=id))

# --- RUTAS DE LOGIN Y SESIÓN PARA VETERINARIOS ---

@app.route('/login/veterinario', methods=['GET', 'POST'])
def login_veterinario():
    error = None
    if request.method == 'POST':
        usuario = request.form.get('usuario')
        contrasena = request.form.get('contrasena')
        try:
            conn = pyodbc.connect(DB_CONFIG)
            cursor = conn.cursor()
            
            # Se compara el texto plano con el VARBINARY(MAX) haciendo CAST a VARCHAR
            cursor.execute(
                """
                SELECT veterinario_id, nombre_completo 
                FROM Veterinarios 
                WHERE usuario = ? 
                  AND CAST(contrasena AS VARCHAR(MAX)) = ? 
                  AND estado = 'Activo'
                """,
                (usuario, contrasena)
            )
            vet = cursor.fetchone()
            cursor.close()
            conn.close()

            if vet:
                session['veterinario_id'] = vet[0]
                session['veterinario_nombre'] = vet[1]
                return redirect(url_for('veterinario_panel'))
            else:
                error = 'Usuario o contraseña incorrectos, o cuenta inactiva.'
        except Exception as e:
            error = f'Error en el sistema de autenticación: {e}'

    return render_template('login_veterinario.html', error=error)

@app.route('/logout/veterinario')
def logout_veterinario():
    session.pop('veterinario_id', None)
    session.pop('veterinario_nombre', None)
    return redirect(url_for('login_veterinario'))

# --- PANEL DEL VETERINARIO PROTEGIDO Y FILTRADO ---

@app.route('/veterinario', methods=['GET'])
def veterinario_panel():
    if not session.get('veterinario_id'):
        return redirect(url_for('login_veterinario'))

    mensaje = None
    consultas = []
    vet_id = session.get('veterinario_id')
    
    try:
        conn = pyodbc.connect(DB_CONFIG)
        cursor = conn.cursor()
        
        # Consultamos únicamente las citas pendientes asignadas a ESTE veterinario logueado
        cursor.execute("""
            SELECT c.consulta_id, m.nombre, m.especie, c.motivo, c.fecha_consulta 
            FROM Consultas c
            JOIN Mascotas m ON c.mascota_id = m.mascota_id
            WHERE c.veterinario_id = ? AND c.estado = 'Programada'
        """, (vet_id,))
        
        consultas = cursor.fetchall()
        cursor.close()
        conn.close()
    except Exception as e:
        mensaje = f"Error al cargar las consultas: {e}"

    return render_template('veterinario_panel.html', consultas=consultas, mensaje=mensaje)

@app.route('/veterinario/atender/<int:consulta_id>', methods=['GET', 'POST'])
def atender_consulta(consulta_id):
    if not session.get('veterinario_id'):
        return redirect(url_for('login_veterinario'))
        
    if request.method == 'POST':
        diagnostico = request.form['diagnostico']
        tratamiento = request.form['tratamiento']
        observaciones = request.form.get('observaciones', 'Ninguna')
        
        try:
            conn = pyodbc.connect(DB_CONFIG)
            cursor = conn.cursor()
            
            cursor.execute(
                "EXEC sp_GenerarTratamiento ?, ?, ?, ?", 
                (consulta_id, diagnostico, tratamiento, observaciones)
            )
            conn.commit()
            cursor.close()
            conn.close()
            return redirect('/veterinario')
        except Exception as e:
            return f"Error al generar el tratamiento cifrado: {e}"

    return render_template('registrar_diagnostico.html', consulta_id=consulta_id)


if __name__ == '__main__':
    app.run(debug=True)