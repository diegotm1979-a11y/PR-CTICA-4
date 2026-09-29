-- ============================================================================
-- SPORTING BANQUILLO — esquema completo de base de datos para Supabase
-- ============================================================================
-- Este script traslada a PostgreSQL (Supabase) el modelo de datos que hoy vive
-- en el almacén clave-valor de sporting-banquillo.html (localStorage / IndexedDB
-- / window.claude.use('db')): las claves 'players', 'staff', 'teams', 'users',
-- 'settings', 'activity', 'videos' y 'matches'.
--
-- Cambios de diseño respecto al almacén actual (recomendados al migrar):
--   1. La autenticación pasa de un usuario/contraseña casero (sha256 guardado
--      en la propia tabla) a Supabase Auth (auth.users). La tabla `profiles`
--      solo guarda el rol y los datos de perfil, enlazada 1:1 con auth.users.
--   2. Las fotos, escudos y vídeos dejan de guardarse como dataURL en JSON y
--      pasan a Supabase Storage (buckets `imagenes` y `videos`); las columnas
--      *_path guardan la ruta dentro del bucket en vez de un blob.
--   3. Las estructuras muy anidadas y de forma libre (el "plan" del partido,
--      las fichas/dibujos de las pizarras) se mantienen como JSONB porque no
--      se consultan por SQL; el resto (jugadores, partidos, convocatorias,
--      goles, minutos, vídeos, clips, eventos de videoanálisis...) se
--      normaliza en tablas de verdad para poder filtrar, unir y proteger con
--      RLS por módulo.
--
-- Orden de ejecución: de arriba a abajo, en una base de datos Supabase nueva.
-- ============================================================================


-- ============================================================================
-- 0. EXTENSIONES
-- ============================================================================
create extension if not exists pgcrypto; -- gen_random_uuid()


-- ============================================================================
-- 1. TIPOS (ENUMS)
-- ============================================================================
-- Roles de cuenta (quién entra en la app) — ROLES en el código.
create type app_role as enum ('Administrador', 'Entrenador', 'Analista', 'Preparador físico', 'Jugador', 'Invitado');

-- Módulos del menú — MODULES en el código.
create type app_module as enum ('plantilla', 'equipos', 'partidos', 'videoteca', 'usuarios', 'ajustes');

-- Niveles de permiso por módulo — PERM_LEVELS en el código (orden = jerarquía).
create type app_perm_level as enum ('sin_acceso', 'ver', 'editar', 'eliminar');

create type player_estado as enum ('disponible', 'lesionado', 'sancionado', 'convocado_internacional');
create type player_pie as enum ('Diestro', 'Zurdo', 'Ambidiestro');
create type match_condicion as enum ('local', 'visitante');
create type squad_status as enum ('titular', 'suplente', 'convocado');
create type evento_tipo_jugada as enum ('gol', 'ocasion');
create type evento_signo as enum ('favor', 'contra');
create type evento_abp as enum ('ofensiva', 'defensiva');
create type video_categoria as enum ('liga', 'pretemporada');
create type clip_categoria as enum ('gol', 'abp', 'presion', 'salida', 'error', 'otro');


-- ============================================================================
-- 2. PERFILES DE USUARIO (sustituye a la tabla 'users' casera)
-- ============================================================================
-- Un perfil por cada auth.users. Se crea solo, ver el trigger más abajo.
create table profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  usuario     text not null unique,
  rol         app_role not null default 'Invitado',
  activo      boolean not null default true,
  foto_path   text, -- ruta dentro del bucket de Storage 'imagenes'
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table profiles is 'Perfil y rol de cada cuenta. La autenticación (contraseña, email) vive en auth.users; esto solo guarda el rol de la app.';


-- ============================================================================
-- 3. PERMISOS POR ROL (sustituye a settings.permissions)
-- ============================================================================
create table role_permissions (
  rol     app_role not null,
  modulo  app_module not null,
  nivel   app_perm_level not null default 'sin_acceso',
  primary key (rol, modulo)
);

comment on table role_permissions is 'Matriz de permisos Rol x Módulo, editable desde Ajustes > Permisos por un Administrador.';

-- Valores por defecto = defaultPermissions() del código.
insert into role_permissions (rol, modulo, nivel) values
  ('Administrador', 'plantilla', 'eliminar'),
  ('Administrador', 'equipos',   'eliminar'),
  ('Administrador', 'partidos',  'eliminar'),
  ('Administrador', 'videoteca', 'eliminar'),
  ('Administrador', 'usuarios',  'eliminar'),
  ('Administrador', 'ajustes',   'eliminar'),

  ('Entrenador', 'plantilla', 'eliminar'),
  ('Entrenador', 'equipos',   'eliminar'),
  ('Entrenador', 'partidos',  'eliminar'),
  ('Entrenador', 'videoteca', 'eliminar'),
  ('Entrenador', 'usuarios',  'ver'),
  ('Entrenador', 'ajustes',   'ver'),

  ('Analista', 'plantilla', 'ver'),
  ('Analista', 'equipos',   'editar'),
  ('Analista', 'partidos',  'editar'),
  ('Analista', 'videoteca', 'editar'),
  ('Analista', 'usuarios',  'sin_acceso'),
  ('Analista', 'ajustes',   'sin_acceso'),

  ('Preparador físico', 'plantilla', 'editar'),
  ('Preparador físico', 'equipos',   'ver'),
  ('Preparador físico', 'partidos',  'ver'),
  ('Preparador físico', 'videoteca', 'ver'),
  ('Preparador físico', 'usuarios',  'sin_acceso'),
  ('Preparador físico', 'ajustes',   'sin_acceso'),

  ('Jugador', 'plantilla', 'ver'),
  ('Jugador', 'equipos',   'ver'),
  ('Jugador', 'partidos',  'ver'),
  ('Jugador', 'videoteca', 'ver'),
  ('Jugador', 'usuarios',  'sin_acceso'),
  ('Jugador', 'ajustes',   'sin_acceso'),

  ('Invitado', 'plantilla', 'ver'),
  ('Invitado', 'equipos',   'ver'),
  ('Invitado', 'partidos',  'sin_acceso'),
  ('Invitado', 'videoteca', 'sin_acceso'),
  ('Invitado', 'usuarios',  'sin_acceso'),
  ('Invitado', 'ajustes',   'sin_acceso');


-- ============================================================================
-- 4. AJUSTES DEL CLUB (sustituye a settings.clubInfo) — fila única
-- ============================================================================
create table club_settings (
  id          int primary key default 1 check (id = 1), -- fuerza que solo exista 1 fila
  nombre      text not null default 'Real Sporting de Gijón',
  temporada   text not null default '2026-27',
  updated_at  timestamptz not null default now()
);

insert into club_settings (id, nombre, temporada) values (1, 'Real Sporting de Gijón', '2026-27');


-- ============================================================================
-- 5. FUNCIONES DE APOYO (permisos y updated_at)
-- ============================================================================
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Peso numérico de cada nivel, para poder pedir "al menos X" (PERM_WEIGHT).
create or replace function perm_weight(nivel app_perm_level)
returns int language sql immutable as $$
  select case nivel
    when 'sin_acceso' then 0
    when 'ver'        then 1
    when 'editar'     then 2
    when 'eliminar'   then 3
  end;
$$;

-- Rol de la cuenta que hace la petición (null si no hay perfil o está desactivada).
-- security definer: evita recursión infinita de RLS al consultar profiles desde
-- las propias políticas de profiles y de las demás tablas.
create or replace function current_app_role()
returns app_role language sql stable security definer set search_path = public as $$
  select rol from profiles where id = auth.uid() and activo = true;
$$;

-- ¿Tiene la cuenta actual, para ese módulo, al menos ese nivel de permiso?
-- Equivale a can(currentUser, settings, modulo, nivel) en el frontend.
create or replace function fn_has_perm(p_modulo app_module, p_nivel_min app_perm_level)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select perm_weight(rp.nivel) >= perm_weight(p_nivel_min)
       from role_permissions rp
      where rp.rol = current_app_role() and rp.modulo = p_modulo),
    false
  );
$$;


-- ============================================================================
-- 6. ALTA AUTOMÁTICA DE PERFIL AL CREAR UN USUARIO EN SUPABASE AUTH
-- ============================================================================
-- El primer usuario que se registre se convierte en Administrador (igual que
-- el "primer arranque" actual de AuthScreen). Los siguientes heredan el rol
-- que se les pase en los metadatos de alta (raw_user_meta_data->>'rol'), o
-- 'Invitado' si no se especifica — para que un alta sin supervisión no reciba
-- permisos de más.
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  es_el_primero boolean;
begin
  select not exists (select 1 from profiles) into es_el_primero;

  insert into profiles (id, usuario, rol, activo)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'usuario', split_part(new.email, '@', 1)),
    case
      when es_el_primero then 'Administrador'::app_role
      else coalesce((new.raw_user_meta_data ->> 'rol')::app_role, 'Invitado'::app_role)
    end,
    true
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

create trigger profiles_set_updated_at
  before update on profiles
  for each row execute function set_updated_at();


-- ============================================================================
-- 7. PLANTILLA: jugadores y cuerpo técnico (módulo 'plantilla')
-- ============================================================================
create table players (
  id                uuid primary key default gen_random_uuid(),
  dorsal            int not null unique,
  nombre            text not null,
  posicion          text not null, -- POR, LD, LI, DFC, LAT, MC, MCO, MCD, MI, MD, EI, ED, DC, SD, '-' (canterano sin definir)
  pie               player_pie,
  fecha_nacimiento  date,
  altura            int, -- cm
  nacionalidad      text,
  estado            player_estado not null default 'disponible',
  notas             text,
  foto_path         text, -- ruta en el bucket 'imagenes'
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create trigger players_set_updated_at before update on players for each row execute function set_updated_at();

create table staff (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null,
  rol         text not null, -- cargo libre: "Entrenador principal", "Segundo entrenador"...
  notas       text,
  foto_path   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger staff_set_updated_at before update on staff for each row execute function set_updated_at();


-- ============================================================================
-- 8. EQUIPOS RIVALES (módulo 'equipos')
-- ============================================================================
create table teams (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null unique,
  competicion   text,
  estadio       text,
  entrenador    text,
  sistema       text, -- uno de SISTEMAS ('4-4-2', '4-3-3', ... o 'Libre'), sin CHECK por si se añaden sistemas nuevos
  colores       text,
  abrev         text,
  color_hex     text,
  notas         text,
  escudo_path   text, -- ruta en el bucket 'imagenes'
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create trigger teams_set_updated_at before update on teams for each row execute function set_updated_at();

-- Plantilla (muy básica) de cada rival, capturada a mano desde la ficha del equipo.
create table team_players (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references teams (id) on delete cascade,
  nombre      text not null,
  dorsal      int,
  posicion    text,
  created_at  timestamptz not null default now()
);

create index team_players_team_id_idx on team_players (team_id);


-- ============================================================================
-- 9. CALENDARIO DE LIGA 2026-27 (datos de referencia, no editables desde la UI)
-- ============================================================================
-- Hoy es una constante fija en el código (SEED_CALENDARIO_2627); se traslada
-- aquí para poder mantenerlo desde la base de datos en vez de tocar el HTML
-- cada temporada. Si se prefiere seguir con la constante en el frontend, esta
-- tabla es opcional.
create table calendario (
  jornada             int primary key,
  fecha               date not null,
  rival               text not null,
  condicion           match_condicion not null,
  derbi               boolean not null default false,
  resultado_local     int,
  resultado_visitante int
);


-- ============================================================================
-- 10. PARTIDOS (módulo 'partidos')
-- ============================================================================
create table matches (
  id                    uuid primary key default gen_random_uuid(),
  rival_id              uuid references teams (id) on delete set null,
  fecha                 date not null,
  hora                  text,
  competicion           text,
  jornada               int,
  condicion             match_condicion,
  estadio               text,

  -- Plan de partido (analisisRival, fases, abp, instrucciones, notas): texto
  -- libre y de forma fija pero no consultado por SQL -> JSONB.
  plan                  jsonb not null default '{
    "analisisRival": {"fortalezas": "", "debilidades": "", "jugadoresClave": ""},
    "fases": {"atqOrg": "", "defOrg": "", "transOf": "", "transDef": ""},
    "abp": {"ofensivo": "", "defensivo": ""},
    "instrucciones": "",
    "notas": ""
  }'::jsonb,

  -- Post-partido (antes postPartido.resultadoLocal/resultadoVisitante/valoracion;
  -- goleadores y minutos se normalizan en match_goles y match_minutos).
  resultado_local       int,
  resultado_visitante   int,
  valoracion            text,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index matches_rival_id_idx on matches (rival_id);
create index matches_fecha_idx on matches (fecha);
create trigger matches_set_updated_at before update on matches for each row execute function set_updated_at();

-- Convocatoria (antes match.convocatoria.{convocados,titulares,suplentes}):
-- una fila por jugador convocado, con su estado. "titular"/"suplente" implican
-- convocado; el resto de convocados sin ficha en el once ni el banquillo
-- quedan como 'convocado'.
create table match_squad (
  id          uuid primary key default gen_random_uuid(),
  match_id    uuid not null references matches (id) on delete cascade,
  player_id   uuid not null references players (id) on delete cascade,
  status      squad_status not null default 'convocado',
  unique (match_id, player_id)
);

create index match_squad_match_id_idx on match_squad (match_id);
create index match_squad_player_id_idx on match_squad (player_id);

-- Pizarras tácticas (antes match.pizarras[]). "fichas" (posiciones x,y de cada
-- jugador en el campograma) y "dibujos" (flechas/zonas/conos/texto dibujados a
-- mano) son de forma libre y solo se leen/escriben tal cual desde el lienzo
-- -> JSONB.
create table pizarras (
  id          uuid primary key default gen_random_uuid(),
  match_id    uuid not null references matches (id) on delete cascade,
  nombre      text not null default 'Principal',
  sistema     text, -- uno de SISTEMAS
  fichas      jsonb not null default '[]'::jsonb, -- [{ playerId, x, y }, ...]
  dibujos     jsonb not null default '[]'::jsonb, -- [{ id, tipo: 'flecha-mov'|'flecha-pase'|'zona'|'cono'|'texto', ... }, ...]
  orden       int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index pizarras_match_id_idx on pizarras (match_id);
create trigger pizarras_set_updated_at before update on pizarras for each row execute function set_updated_at();

-- Goleadores del partido (antes postPartido.goleadores[]).
create table match_goles (
  id          uuid primary key default gen_random_uuid(),
  match_id    uuid not null references matches (id) on delete cascade,
  player_id   uuid references players (id) on delete set null,
  minuto      int,
  created_at  timestamptz not null default now()
);

create index match_goles_match_id_idx on match_goles (match_id);

-- Minutos jugados por cada convocado (antes postPartido.minutos = { [playerId]: minutos }).
create table match_minutos (
  match_id    uuid not null references matches (id) on delete cascade,
  player_id   uuid not null references players (id) on delete cascade,
  minutos     int not null default 0,
  primary key (match_id, player_id)
);


-- ============================================================================
-- 11. VIDEOTECA (módulo 'videoteca')
-- ============================================================================
create table videos (
  id                  uuid primary key default gen_random_uuid(),
  categoria           video_categoria not null,
  jornada             int,             -- solo si categoria = 'liga'
  pretemporada_num    int,             -- solo si categoria = 'pretemporada'
  titulo              text not null,
  descripcion         text,
  fecha               date,
  etiquetas           text[] not null default '{}',
  url                 text,            -- enlace externo (YouTube, etc.)
  archivo_path        text,            -- ruta en el bucket 'videos', si se sube archivo propio
  archivo_nombre      text,
  match_id            uuid references matches (id) on delete set null,
  rival_id            uuid references teams (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (url is not null or archivo_path is not null)
);

create index videos_match_id_idx on videos (match_id);
create index videos_rival_id_idx on videos (rival_id);
create trigger videos_set_updated_at before update on videos for each row execute function set_updated_at();

-- Jugadores vinculados a un vídeo (antes video.jugadores[]).
create table video_player_tags (
  video_id    uuid not null references videos (id) on delete cascade,
  player_id   uuid not null references players (id) on delete cascade,
  primary key (video_id, player_id)
);

-- Clips manuales dentro de un vídeo (antes video.clips[]).
create table video_clips (
  id          uuid primary key default gen_random_uuid(),
  video_id    uuid not null references videos (id) on delete cascade,
  inicio      int not null, -- segundos
  fin         int,          -- segundos, opcional
  categoria   clip_categoria not null default 'otro',
  nota        text,
  created_at  timestamptz not null default now()
);

create index video_clips_video_id_idx on video_clips (video_id);

-- Eventos de videoanálisis marcados sobre el campograma (antes
-- videos.analisis[videoId] = [eventos]).
create table video_analysis_events (
  id            uuid primary key default gen_random_uuid(),
  video_id      uuid not null references videos (id) on delete cascade,
  parte         int,             -- 1ª/2ª parte
  inicio        numeric not null, -- segundos (clip: 5s antes del marcado)
  fin           numeric not null, -- segundos (clip: 15s después del marcado)
  tipo_jugada   evento_tipo_jugada, -- 'gol' | 'ocasion', puede quedar sin rellenar
  signo         evento_signo,       -- 'favor' | 'contra', puede quedar sin rellenar
  abp           evento_abp,         -- 'ofensiva' | 'defensiva', si es jugada a balón parado
  individual    boolean not null default false,
  player_id     uuid references players (id) on delete set null,
  pos_x         numeric, -- posición en el campo, % ancho (posicion_campo.x)
  pos_y         numeric, -- posición en el campo, % alto (posicion_campo.y)
  created_at    timestamptz not null default now()
);

create index video_analysis_events_video_id_idx on video_analysis_events (video_id);


-- ============================================================================
-- 12. REGISTRO DE ACTIVIDAD (pestaña Actividad, dentro del módulo 'usuarios')
-- ============================================================================
create table activity_log (
  id              bigint generated always as identity primary key,
  user_id         uuid references profiles (id) on delete set null,
  usuario_nombre  text, -- copia del nombre de usuario en el momento del hecho, por si el perfil se borra luego
  accion          text not null,
  detalle         text,
  created_at      timestamptz not null default now()
);

create index activity_log_created_at_idx on activity_log (created_at desc);


-- ============================================================================
-- 13. SEGURIDAD A NIVEL DE FILA (RLS), según la matriz Rol x Módulo
-- ============================================================================
-- Patrón repetido para cada módulo: 'ver' habilita SELECT, 'editar' habilita
-- INSERT/UPDATE, 'eliminar' habilita DELETE — igual que canDo(modulo, nivel)
-- en el frontend.

-- --- profiles (módulo 'usuarios', con excepción: cada cuenta ve/edita la suya) ---
alter table profiles enable row level security;

create policy profiles_select on profiles for select
  using (id = auth.uid() or fn_has_perm('usuarios', 'ver'));

-- Sin política de INSERT: los perfiles solo los crea el trigger on_auth_user_created.
create policy profiles_update on profiles for update
  using (id = auth.uid() or fn_has_perm('usuarios', 'editar'))
  with check (id = auth.uid() or fn_has_perm('usuarios', 'editar'));

create policy profiles_delete on profiles for delete
  using (fn_has_perm('usuarios', 'eliminar'));

-- La política anterior deja que cada cuenta actualice su propia fila (para
-- poder cambiar su usuario/foto sin depender de un administrador), pero eso
-- por sí solo permitiría que cualquiera se autoasignara el rol Administrador.
-- Este trigger bloquea el cambio de rol/activo salvo que quien edita ya tenga
-- permiso de 'usuarios' > editar (es decir, que no sea una auto-edición).
create or replace function profiles_guard_privileged_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.rol is distinct from old.rol or new.activo is distinct from old.activo)
     and not fn_has_perm('usuarios', 'editar') then
    raise exception 'No tienes permiso para cambiar el rol o el estado de esta cuenta';
  end if;
  return new;
end;
$$;

create trigger profiles_guard_privileged_fields_trg
  before update on profiles
  for each row execute function profiles_guard_privileged_fields();

-- --- role_permissions (todo el mundo necesita leer su propia fila para saber
-- qué puede hacer; solo Ajustes > editar puede tocar la matriz) ---
alter table role_permissions enable row level security;

create policy role_permissions_select on role_permissions for select
  using (auth.role() = 'authenticated');

create policy role_permissions_write on role_permissions for all
  using (fn_has_perm('ajustes', 'editar'))
  with check (fn_has_perm('ajustes', 'editar'));

-- --- club_settings ---
alter table club_settings enable row level security;

create policy club_settings_select on club_settings for select
  using (auth.role() = 'authenticated');

create policy club_settings_write on club_settings for all
  using (fn_has_perm('ajustes', 'editar'))
  with check (fn_has_perm('ajustes', 'editar'));

-- --- plantilla: players, staff ---
alter table players enable row level security;
create policy players_select on players for select using (fn_has_perm('plantilla', 'ver'));
create policy players_insert on players for insert with check (fn_has_perm('plantilla', 'editar'));
create policy players_update on players for update using (fn_has_perm('plantilla', 'editar')) with check (fn_has_perm('plantilla', 'editar'));
create policy players_delete on players for delete using (fn_has_perm('plantilla', 'eliminar'));

alter table staff enable row level security;
create policy staff_select on staff for select using (fn_has_perm('plantilla', 'ver'));
create policy staff_insert on staff for insert with check (fn_has_perm('plantilla', 'editar'));
create policy staff_update on staff for update using (fn_has_perm('plantilla', 'editar')) with check (fn_has_perm('plantilla', 'editar'));
create policy staff_delete on staff for delete using (fn_has_perm('plantilla', 'eliminar'));

-- --- equipos: teams, team_players ---
alter table teams enable row level security;
create policy teams_select on teams for select using (fn_has_perm('equipos', 'ver'));
create policy teams_insert on teams for insert with check (fn_has_perm('equipos', 'editar'));
create policy teams_update on teams for update using (fn_has_perm('equipos', 'editar')) with check (fn_has_perm('equipos', 'editar'));
create policy teams_delete on teams for delete using (fn_has_perm('equipos', 'eliminar'));

alter table team_players enable row level security;
create policy team_players_select on team_players for select using (fn_has_perm('equipos', 'ver'));
create policy team_players_insert on team_players for insert with check (fn_has_perm('equipos', 'editar'));
create policy team_players_update on team_players for update using (fn_has_perm('equipos', 'editar')) with check (fn_has_perm('equipos', 'editar'));
create policy team_players_delete on team_players for delete using (fn_has_perm('equipos', 'eliminar'));

-- --- partidos: calendario, matches, match_squad, pizarras, match_goles, match_minutos ---
alter table calendario enable row level security;
create policy calendario_select on calendario for select using (fn_has_perm('partidos', 'ver'));
create policy calendario_write on calendario for all using (fn_has_perm('partidos', 'editar')) with check (fn_has_perm('partidos', 'editar'));

alter table matches enable row level security;
create policy matches_select on matches for select using (fn_has_perm('partidos', 'ver'));
create policy matches_insert on matches for insert with check (fn_has_perm('partidos', 'editar'));
create policy matches_update on matches for update using (fn_has_perm('partidos', 'editar')) with check (fn_has_perm('partidos', 'editar'));
create policy matches_delete on matches for delete using (fn_has_perm('partidos', 'eliminar'));

alter table match_squad enable row level security;
create policy match_squad_select on match_squad for select using (fn_has_perm('partidos', 'ver'));
create policy match_squad_insert on match_squad for insert with check (fn_has_perm('partidos', 'editar'));
create policy match_squad_update on match_squad for update using (fn_has_perm('partidos', 'editar')) with check (fn_has_perm('partidos', 'editar'));
create policy match_squad_delete on match_squad for delete using (fn_has_perm('partidos', 'eliminar'));

alter table pizarras enable row level security;
create policy pizarras_select on pizarras for select using (fn_has_perm('partidos', 'ver'));
create policy pizarras_insert on pizarras for insert with check (fn_has_perm('partidos', 'editar'));
create policy pizarras_update on pizarras for update using (fn_has_perm('partidos', 'editar')) with check (fn_has_perm('partidos', 'editar'));
create policy pizarras_delete on pizarras for delete using (fn_has_perm('partidos', 'eliminar'));

alter table match_goles enable row level security;
create policy match_goles_select on match_goles for select using (fn_has_perm('partidos', 'ver'));
create policy match_goles_insert on match_goles for insert with check (fn_has_perm('partidos', 'editar'));
create policy match_goles_update on match_goles for update using (fn_has_perm('partidos', 'editar')) with check (fn_has_perm('partidos', 'editar'));
create policy match_goles_delete on match_goles for delete using (fn_has_perm('partidos', 'eliminar'));

alter table match_minutos enable row level security;
create policy match_minutos_select on match_minutos for select using (fn_has_perm('partidos', 'ver'));
create policy match_minutos_insert on match_minutos for insert with check (fn_has_perm('partidos', 'editar'));
create policy match_minutos_update on match_minutos for update using (fn_has_perm('partidos', 'editar')) with check (fn_has_perm('partidos', 'editar'));
create policy match_minutos_delete on match_minutos for delete using (fn_has_perm('partidos', 'eliminar'));

-- --- videoteca: videos, video_player_tags, video_clips, video_analysis_events ---
alter table videos enable row level security;
create policy videos_select on videos for select using (fn_has_perm('videoteca', 'ver'));
create policy videos_insert on videos for insert with check (fn_has_perm('videoteca', 'editar'));
create policy videos_update on videos for update using (fn_has_perm('videoteca', 'editar')) with check (fn_has_perm('videoteca', 'editar'));
create policy videos_delete on videos for delete using (fn_has_perm('videoteca', 'eliminar'));

alter table video_player_tags enable row level security;
create policy video_player_tags_select on video_player_tags for select using (fn_has_perm('videoteca', 'ver'));
create policy video_player_tags_insert on video_player_tags for insert with check (fn_has_perm('videoteca', 'editar'));
create policy video_player_tags_update on video_player_tags for update using (fn_has_perm('videoteca', 'editar')) with check (fn_has_perm('videoteca', 'editar'));
create policy video_player_tags_delete on video_player_tags for delete using (fn_has_perm('videoteca', 'eliminar'));

alter table video_clips enable row level security;
create policy video_clips_select on video_clips for select using (fn_has_perm('videoteca', 'ver'));
create policy video_clips_insert on video_clips for insert with check (fn_has_perm('videoteca', 'editar'));
create policy video_clips_update on video_clips for update using (fn_has_perm('videoteca', 'editar')) with check (fn_has_perm('videoteca', 'editar'));
create policy video_clips_delete on video_clips for delete using (fn_has_perm('videoteca', 'eliminar'));

alter table video_analysis_events enable row level security;
create policy video_analysis_events_select on video_analysis_events for select using (fn_has_perm('videoteca', 'ver'));
create policy video_analysis_events_insert on video_analysis_events for insert with check (fn_has_perm('videoteca', 'editar'));
create policy video_analysis_events_update on video_analysis_events for update using (fn_has_perm('videoteca', 'editar')) with check (fn_has_perm('videoteca', 'editar'));
create policy video_analysis_events_delete on video_analysis_events for delete using (fn_has_perm('videoteca', 'eliminar'));

-- --- activity_log: lectura solo con permiso de 'usuarios', pero cualquier
-- cuenta autenticada puede registrar su propia actividad (todas las pantallas
-- llaman a pushActivity, no solo la de Usuarios) ---
alter table activity_log enable row level security;

create policy activity_log_select on activity_log for select
  using (fn_has_perm('usuarios', 'ver'));

create policy activity_log_insert on activity_log for insert
  with check (auth.uid() is not null and (user_id is null or user_id = auth.uid()));

-- Sin políticas de UPDATE/DELETE: el histórico de actividad es de solo lectura.


-- ============================================================================
-- 14. STORAGE: fotos, escudos y vídeos (sustituye a las claves 'photo:'/'video:')
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('imagenes', 'imagenes', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('videos', 'videos', false)
on conflict (id) do nothing;

-- 'imagenes': fotos de jugadores/staff (módulo 'plantilla') y escudos de
-- equipos rivales (módulo 'equipos'). Lectura pública porque son imágenes de
-- perfil sin datos sensibles; escritura restringida por permiso.
create policy imagenes_select on storage.objects for select
  using (bucket_id = 'imagenes');

create policy imagenes_insert on storage.objects for insert
  with check (bucket_id = 'imagenes' and (fn_has_perm('plantilla', 'editar') or fn_has_perm('equipos', 'editar')));

create policy imagenes_update on storage.objects for update
  using (bucket_id = 'imagenes' and (fn_has_perm('plantilla', 'editar') or fn_has_perm('equipos', 'editar')))
  with check (bucket_id = 'imagenes' and (fn_has_perm('plantilla', 'editar') or fn_has_perm('equipos', 'editar')));

create policy imagenes_delete on storage.objects for delete
  using (bucket_id = 'imagenes' and (fn_has_perm('plantilla', 'eliminar') or fn_has_perm('equipos', 'eliminar')));

-- 'videos': archivos de partido/videoanálisis subidos a mano (módulo
-- 'videoteca'). Privado: solo lo lee quien tenga al menos permiso de 'ver'.
create policy videos_bucket_select on storage.objects for select
  using (bucket_id = 'videos' and fn_has_perm('videoteca', 'ver'));

create policy videos_bucket_insert on storage.objects for insert
  with check (bucket_id = 'videos' and fn_has_perm('videoteca', 'editar'));

create policy videos_bucket_update on storage.objects for update
  using (bucket_id = 'videos' and fn_has_perm('videoteca', 'editar'))
  with check (bucket_id = 'videos' and fn_has_perm('videoteca', 'editar'));

create policy videos_bucket_delete on storage.objects for delete
  using (bucket_id = 'videos' and fn_has_perm('videoteca', 'eliminar'));


-- ============================================================================
-- 15. DATOS INICIALES (opcional) — misma plantilla, rivales y calendario que
--     hoy generan SEED_PLAYERS / SEED_STAFF / SEED_TEAMS / SEED_CALENDARIO_2627
--     en el HTML, para arrancar con los mismos datos de ejemplo.
-- ============================================================================
-- Jugadores de la plantilla (temporada 2026-27)
insert into players (dorsal, nombre, posicion, estado, notas) values
  (1, 'Rubén Yáñez', 'POR', 'disponible', NULL),
  (13, 'Egoitz Arana', 'POR', 'disponible', NULL),
  (2, 'Guille Rosas', 'LD', 'disponible', NULL),
  (3, 'Pablo García', 'LI', 'disponible', NULL),
  (4, 'Emanuel Gularte', 'DFC', 'disponible', NULL),
  (5, 'Diego Sánchez', 'DFC', 'disponible', NULL),
  (15, 'Pablo Vázquez', 'DFC', 'disponible', NULL),
  (23, 'Jorge Sáenz', 'DFC', 'disponible', NULL),
  (24, 'Aimar Duñabeitia', 'DFC', 'disponible', NULL),
  (44, 'Andrés Cuenca', 'DFC', 'disponible', NULL),
  (6, 'Nacho Martín', 'MC', 'disponible', NULL),
  (8, 'Manu Rodríguez', 'MC', 'disponible', NULL),
  (10, 'César Gelabert', 'MCO', 'disponible', NULL),
  (14, 'Àlex Corredera', 'MC', 'disponible', NULL),
  (21, 'Mamadou Loum', 'MCD', 'disponible', NULL),
  (22, 'Hugo Guillamón', 'MCD', 'disponible', NULL),
  (7, 'Gaspar Campos', 'EI', 'disponible', NULL),
  (11, 'Konrad de la Fuente', 'EI', 'disponible', NULL),
  (20, 'Nikita Iosifov', 'EI', 'disponible', NULL),
  (9, 'Andrés Ferrari', 'DC', 'lesionado', NULL),
  (16, 'Alejo Sarco', 'DC', 'disponible', NULL),
  (17, 'Antonio Casas', 'DC', 'disponible', NULL),
  (19, 'Juan Otero', 'DC', 'disponible', NULL),
  (26, 'Iker Martínez', '-', 'disponible', 'Canterano');

-- Cuerpo técnico
insert into staff (nombre, rol, notas) values
  ('Nicolás Larcamón', 'Entrenador principal', NULL);

-- Rivales de LaLiga Hypermotion 2026-27
insert into teams (nombre, competicion, estadio, abrev, color_hex) values
  ('CE Sabadell FC', 'Segunda División', 'Estadi Nova Creu Alta', 'SAB', '#c8102e'),
  ('Burgos CF', 'Segunda División', 'El Plantío', 'BUR', '#1a1a1a'),
  ('CD Tenerife', 'Segunda División', 'Heliodoro Rodríguez López', 'TFE', '#0033a0'),
  ('Girona FC', 'Segunda División', 'Montilivi', 'GIR', '#cc0000'),
  ('CD Eldense', 'Segunda División', 'Nuevo Pepico Amat', 'ELD', '#003da5'),
  ('FC Andorra', 'Segunda División', 'Estadi Nacional', 'AND', '#004b93'),
  ('Real Oviedo', 'Segunda División', 'Carlos Tartiere', 'OVI', '#1c3f94'),
  ('Celta Fortuna', 'Segunda División', 'A Madroa', 'CEL', '#2a9df4'),
  ('Cádiz CF', 'Segunda División', 'Nuevo Mirandilla', 'CAD', '#f2c500'),
  ('Albacete Balompié', 'Segunda División', 'Carlos Belmonte', 'ALB', '#d0021b'),
  ('CD Castellón', 'Segunda División', 'Nou Castalia', 'CAS', '#046a38'),
  ('AD Ceuta FC', 'Segunda División', 'Alfonso Murube', 'CEU', '#004b87'),
  ('Real Valladolid', 'Segunda División', 'José Zorrilla', 'VLL', '#5b2a86'),
  ('Real Sociedad B', 'Segunda División', 'Zubieta', 'RSB', '#0058a8'),
  ('UD Las Palmas', 'Segunda División', 'Gran Canaria', 'LPA', '#ffcd00'),
  ('UD Almería', 'Segunda División', 'Power Horse Stadium', 'ALM', '#d81920'),
  ('Granada CF', 'Segunda División', 'Nuevo Los Cármenes', 'GRA', '#c60c30'),
  ('SD Eibar', 'Segunda División', 'Ipurua', 'EIB', '#00335e'),
  ('CD Leganés', 'Segunda División', 'Butarque', 'LEG', '#0072ce'),
  ('RCD Mallorca', 'Segunda División', 'Son Moix', 'MLL', '#e2001a'),
  ('Córdoba CF', 'Segunda División', 'Nuevo Arcángel', 'COR', '#1a7a3c');

-- Calendario oficial 2026-27 (42 jornadas)
insert into calendario (jornada, fecha, rival, condicion, derbi, resultado_local, resultado_visitante) values
  (1, '2026-08-17', 'CE Sabadell FC', 'local', false, 0, 0),
  (2, '2026-08-23', 'Burgos CF', 'local', false, 1, 0),
  (3, '2026-08-28', 'CD Tenerife', 'visitante', false, 0, 1),
  (4, '2026-09-05', 'Girona FC', 'local', false, 0, 2),
  (5, '2026-09-13', 'CD Eldense', 'local', false, 0, 1),
  (6, '2026-09-19', 'FC Andorra', 'visitante', false, 1, 3),
  (7, '2026-09-27', 'Real Oviedo', 'visitante', true, 2, 0),
  (8, '2026-10-04', 'Celta Fortuna', 'local', false, NULL, NULL),
  (9, '2026-10-11', 'Cádiz CF', 'visitante', false, NULL, NULL),
  (10, '2026-10-18', 'Albacete Balompié', 'local', false, NULL, NULL),
  (11, '2026-10-25', 'CD Castellón', 'visitante', false, NULL, NULL),
  (12, '2026-11-01', 'AD Ceuta FC', 'visitante', false, NULL, NULL),
  (13, '2026-11-08', 'Real Valladolid', 'local', false, NULL, NULL),
  (14, '2026-11-15', 'Real Sociedad B', 'visitante', false, NULL, NULL),
  (15, '2026-11-22', 'UD Las Palmas', 'local', false, NULL, NULL),
  (16, '2026-11-29', 'UD Almería', 'visitante', false, NULL, NULL),
  (17, '2026-12-06', 'Granada CF', 'local', false, NULL, NULL),
  (18, '2026-12-13', 'SD Eibar', 'visitante', false, NULL, NULL),
  (19, '2026-12-20', 'CD Leganés', 'local', false, NULL, NULL),
  (20, '2027-01-03', 'RCD Mallorca', 'visitante', false, NULL, NULL),
  (21, '2027-01-10', 'Córdoba CF', 'local', false, NULL, NULL),
  (22, '2027-01-17', 'Burgos CF', 'visitante', false, NULL, NULL),
  (23, '2027-01-24', 'CD Castellón', 'local', false, NULL, NULL),
  (24, '2027-01-31', 'UD Las Palmas', 'visitante', false, NULL, NULL),
  (25, '2027-02-07', 'AD Ceuta FC', 'local', false, NULL, NULL),
  (26, '2027-02-14', 'Real Valladolid', 'visitante', false, NULL, NULL),
  (27, '2027-02-21', 'FC Andorra', 'local', false, NULL, NULL),
  (28, '2027-02-28', 'Girona FC', 'visitante', false, NULL, NULL),
  (29, '2027-03-07', 'Cádiz CF', 'local', false, NULL, NULL),
  (30, '2027-03-14', 'CD Eldense', 'visitante', false, NULL, NULL),
  (31, '2027-03-21', 'RCD Mallorca', 'local', false, NULL, NULL),
  (32, '2027-03-28', 'Celta Fortuna', 'visitante', false, NULL, NULL),
  (33, '2027-04-04', 'CD Tenerife', 'local', false, NULL, NULL),
  (34, '2027-04-11', 'Real Sociedad B', 'local', false, NULL, NULL),
  (35, '2027-04-18', 'CE Sabadell FC', 'visitante', false, NULL, NULL),
  (36, '2027-04-25', 'Real Oviedo', 'local', true, NULL, NULL),
  (37, '2027-05-02', 'CD Leganés', 'visitante', false, NULL, NULL),
  (38, '2027-05-09', 'Granada CF', 'visitante', false, NULL, NULL),
  (39, '2027-05-16', 'SD Eibar', 'local', false, NULL, NULL),
  (40, '2027-05-23', 'Albacete Balompié', 'visitante', false, NULL, NULL),
  (41, '2027-05-30', 'UD Almería', 'local', false, NULL, NULL),
  (42, '2027-06-06', 'Córdoba CF', 'visitante', false, NULL, NULL);

-- Nota: no se inserta ningún usuario aquí. La primera cuenta que se registre
-- con Supabase Auth se convierte automáticamente en Administrador (ver el
-- trigger handle_new_user de la sección 6).
