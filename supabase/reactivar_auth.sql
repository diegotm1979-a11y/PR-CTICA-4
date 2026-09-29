-- ============================================================================
-- REACTIVAR AUTENTICACIÓN — deshace supabase/bypass_auth_TEMP.sql y devuelve
-- la seguridad real (RLS por rol) de schema.sql. Ejecutar en el SQL Editor de
-- Supabase, junto con REQUIRE_AUTH = true en sporting-banquillo.html.
-- ============================================================================

create or replace function fn_has_perm(p_modulo app_module, p_nivel_min app_perm_level)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select perm_weight(rp.nivel) >= perm_weight(p_nivel_min)
       from role_permissions rp
      where rp.rol = current_app_role() and rp.modulo = p_modulo),
    false
  );
$$;

drop policy if exists role_permissions_select on role_permissions;
create policy role_permissions_select on role_permissions for select
  using (auth.role() = 'authenticated');

drop policy if exists club_settings_select on club_settings;
create policy club_settings_select on club_settings for select
  using (auth.role() = 'authenticated');
