-- ============================================================================
-- KV_STORE — documentos JSON para plantilla, equipos, partidos, vídeos y
-- actividad, pensado para sporting-banquillo.html tal y como está hoy.
-- ============================================================================
-- Requiere haber ejecutado antes supabase/schema.sql (usa sus tipos app_module
-- y su función set_updated_at, y depende de que existan profiles/role_permissions).
--
-- Por qué esta tabla y no las tablas normalizadas (players, matches, videos...)
-- del primer esquema: adaptar sporting-banquillo.html para que hable con esas
-- tablas relacionales habría supuesto reescribir buena parte de las 4500 líneas
-- del archivo (cada pantalla trabaja con arrays/objetos anidados en memoria).
-- En vez de eso, storageGet/storageSet ahora leen y escriben un documento JSON
-- por clave en esta tabla — el mismo documento que antes vivía en localStorage
-- — así que ninguna pantalla ha tenido que cambiar. Las tablas del primer
-- esquema (players, staff, teams, matches, videos...) se quedan sin usar; no
-- pasa nada por dejarlas ahí, y siempre se puede hacer esa normalización más
-- adelante si algún día hace falta consultarlas con SQL. profiles,
-- role_permissions y club_settings SÍ se usan (identidad y ajustes).
-- ============================================================================

create table kv_store (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now()
);

create trigger kv_store_set_updated_at
  before update on kv_store
  for each row execute function set_updated_at();

-- A qué módulo de permisos pertenece cada clave.
create or replace function kv_modulo(k text)
returns app_module language sql immutable as $$
  select case
    when k in ('players', 'staff') then 'plantilla'::app_module
    when k = 'teams' then 'equipos'::app_module
    when k = 'matches' then 'partidos'::app_module
    when k = 'videos' then 'videoteca'::app_module
    when k = 'activity' then 'usuarios'::app_module
  end;
$$;

alter table kv_store enable row level security;

create policy kv_store_select on kv_store for select
  using (fn_has_perm(kv_modulo(key), 'ver'));

-- Solo se permite ACTUALIZAR filas (se crean todas más abajo, de una vez, por
-- SQL), nunca insertar ni borrar desde el cliente. 'activity' es un caso
-- especial: cualquier cuenta autenticada puede añadir su propia entrada al
-- registro de actividad, tenga o no permiso sobre 'usuarios' (todas las
-- pantallas registran actividad, no solo la de Usuarios).
create policy kv_store_update on kv_store for update
  using (case when key = 'activity' then auth.uid() is not null else fn_has_perm(kv_modulo(key), 'editar') end)
  with check (case when key = 'activity' then auth.uid() is not null else fn_has_perm(kv_modulo(key), 'editar') end);

-- Datos iniciales: la misma plantilla, cuerpo técnico y rivales que hoy trae
-- SEED_PLAYERS/SEED_STAFF/SEED_TEAMS en el HTML. 'matches', 'videos' y
-- 'activity' arrancan vacíos.
insert into kv_store (key, value) values
  ('players', '[{"id":"j_nasnnxzskhl","dorsal":1,"nombre":"Rubén Yáñez","posicion":"POR","linea":"POR","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_xxpjabmskhl","dorsal":13,"nombre":"Egoitz Arana","posicion":"POR","linea":"POR","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_usbq6k5skhl","dorsal":2,"nombre":"Guille Rosas","posicion":"LD","linea":"DEF","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_dgzz10hskhl","dorsal":3,"nombre":"Pablo García","posicion":"LI","linea":"DEF","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_drzls2xskhl","dorsal":4,"nombre":"Emanuel Gularte","posicion":"DFC","linea":"DEF","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_iugj2epskhl","dorsal":5,"nombre":"Diego Sánchez","posicion":"DFC","linea":"DEF","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_fpsgc6gskhl","dorsal":15,"nombre":"Pablo Vázquez","posicion":"DFC","linea":"DEF","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_gizjfjlskhl","dorsal":23,"nombre":"Jorge Sáenz","posicion":"DFC","linea":"DEF","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_iff8nx7skhl","dorsal":24,"nombre":"Aimar Duñabeitia","posicion":"DFC","linea":"DEF","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_s3fnojfskhl","dorsal":44,"nombre":"Andrés Cuenca","posicion":"DFC","linea":"DEF","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_7i39acuskhl","dorsal":6,"nombre":"Nacho Martín","posicion":"MC","linea":"MED","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_azdohh6skhl","dorsal":8,"nombre":"Manu Rodríguez","posicion":"MC","linea":"MED","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_efdf7e4skhl","dorsal":10,"nombre":"César Gelabert","posicion":"MCO","linea":"MED","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_xzfu3tzskhl","dorsal":14,"nombre":"Àlex Corredera","posicion":"MC","linea":"MED","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_5kdnfrmskhl","dorsal":21,"nombre":"Mamadou Loum","posicion":"MCD","linea":"MED","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_ervq0joskhl","dorsal":22,"nombre":"Hugo Guillamón","posicion":"MCD","linea":"MED","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_567291mskhl","dorsal":7,"nombre":"Gaspar Campos","posicion":"EI","linea":"DEL","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_pogtil4skhl","dorsal":11,"nombre":"Konrad de la Fuente","posicion":"EI","linea":"DEL","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_it6g2j4skhl","dorsal":20,"nombre":"Nikita Iosifov","posicion":"EI","linea":"DEL","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_rpf1jo8skhl","dorsal":9,"nombre":"Andrés Ferrari","posicion":"DC","linea":"DEL","estado":"lesionado","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_cpn9di6skhl","dorsal":16,"nombre":"Alejo Sarco","posicion":"DC","linea":"DEL","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_7agfrwoskhl","dorsal":17,"nombre":"Antonio Casas","posicion":"DC","linea":"DEL","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_w2wauubskhl","dorsal":19,"nombre":"Juan Otero","posicion":"DC","linea":"DEL","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"","fotoKey":null},{"id":"j_hvjcepsskhl","dorsal":26,"nombre":"Iker Martínez","posicion":"-","linea":"SIN","estado":"disponible","pie":"","fechaNacimiento":"","altura":"","nacionalidad":"","notas":"Canterano","fotoKey":null}]'::jsonb),
  ('staff', '[{"id":"s_dc1a8idskhl","nombre":"Nicolás Larcamón","rol":"Entrenador principal","notas":"","fotoKey":null}]'::jsonb),
  ('teams', '[{"id":"r_be5405kskhm","nombre":"CE Sabadell FC","competicion":"Segunda División","estadio":"Estadi Nova Creu Alta","entrenador":"","sistema":"","colores":"","abrev":"SAB","colorHex":"#c8102e","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_ww24jw6skhm","nombre":"Burgos CF","competicion":"Segunda División","estadio":"El Plantío","entrenador":"","sistema":"","colores":"","abrev":"BUR","colorHex":"#1a1a1a","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_czkmn5xskhm","nombre":"CD Tenerife","competicion":"Segunda División","estadio":"Heliodoro Rodríguez López","entrenador":"","sistema":"","colores":"","abrev":"TFE","colorHex":"#0033a0","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_ebp9dmnskhm","nombre":"Girona FC","competicion":"Segunda División","estadio":"Montilivi","entrenador":"","sistema":"","colores":"","abrev":"GIR","colorHex":"#cc0000","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_qva4lvlskhm","nombre":"CD Eldense","competicion":"Segunda División","estadio":"Nuevo Pepico Amat","entrenador":"","sistema":"","colores":"","abrev":"ELD","colorHex":"#003da5","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_zewidypskhm","nombre":"FC Andorra","competicion":"Segunda División","estadio":"Estadi Nacional","entrenador":"","sistema":"","colores":"","abrev":"AND","colorHex":"#004b93","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_ht0v8ydskhm","nombre":"Real Oviedo","competicion":"Segunda División","estadio":"Carlos Tartiere","entrenador":"","sistema":"","colores":"","abrev":"OVI","colorHex":"#1c3f94","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_rtfxac7skhm","nombre":"Celta Fortuna","competicion":"Segunda División","estadio":"A Madroa","entrenador":"","sistema":"","colores":"","abrev":"CEL","colorHex":"#2a9df4","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_p2gnd19skhm","nombre":"Cádiz CF","competicion":"Segunda División","estadio":"Nuevo Mirandilla","entrenador":"","sistema":"","colores":"","abrev":"CAD","colorHex":"#f2c500","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_kdu7urnskhm","nombre":"Albacete Balompié","competicion":"Segunda División","estadio":"Carlos Belmonte","entrenador":"","sistema":"","colores":"","abrev":"ALB","colorHex":"#d0021b","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_iulqv34skhm","nombre":"CD Castellón","competicion":"Segunda División","estadio":"Nou Castalia","entrenador":"","sistema":"","colores":"","abrev":"CAS","colorHex":"#046a38","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_7a0imfbskhm","nombre":"AD Ceuta FC","competicion":"Segunda División","estadio":"Alfonso Murube","entrenador":"","sistema":"","colores":"","abrev":"CEU","colorHex":"#004b87","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_dwj90hyskhm","nombre":"Real Valladolid","competicion":"Segunda División","estadio":"José Zorrilla","entrenador":"","sistema":"","colores":"","abrev":"VLL","colorHex":"#5b2a86","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_ouf0dcsskhm","nombre":"Real Sociedad B","competicion":"Segunda División","estadio":"Zubieta","entrenador":"","sistema":"","colores":"","abrev":"RSB","colorHex":"#0058a8","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_i7bdk4bskhm","nombre":"UD Las Palmas","competicion":"Segunda División","estadio":"Gran Canaria","entrenador":"","sistema":"","colores":"","abrev":"LPA","colorHex":"#ffcd00","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_f9c9gjtskhm","nombre":"UD Almería","competicion":"Segunda División","estadio":"Power Horse Stadium","entrenador":"","sistema":"","colores":"","abrev":"ALM","colorHex":"#d81920","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_5bf75w5skhm","nombre":"Granada CF","competicion":"Segunda División","estadio":"Nuevo Los Cármenes","entrenador":"","sistema":"","colores":"","abrev":"GRA","colorHex":"#c60c30","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_2w2ilfcskhm","nombre":"SD Eibar","competicion":"Segunda División","estadio":"Ipurua","entrenador":"","sistema":"","colores":"","abrev":"EIB","colorHex":"#00335e","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_lt455owskhm","nombre":"CD Leganés","competicion":"Segunda División","estadio":"Butarque","entrenador":"","sistema":"","colores":"","abrev":"LEG","colorHex":"#0072ce","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_0ive3fdskhm","nombre":"RCD Mallorca","competicion":"Segunda División","estadio":"Son Moix","entrenador":"","sistema":"","colores":"","abrev":"MLL","colorHex":"#e2001a","notas":"","escudoKey":null,"jugadores":[]},{"id":"r_4doultpskhm","nombre":"Córdoba CF","competicion":"Segunda División","estadio":"Nuevo Arcángel","entrenador":"","sistema":"","colores":"","abrev":"COR","colorHex":"#1a7a3c","notas":"","escudoKey":null,"jugadores":[]}]'::jsonb),
  ('matches', '[]'::jsonb),
  ('videos', '{"items":[]}'::jsonb),
  ('activity', '[]'::jsonb);
