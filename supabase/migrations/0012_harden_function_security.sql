-- Phase 3 hardening: lock down trigger-only functions.
--
-- The Supabase advisors correctly flagged that fn_audit_trail,
-- fn_log_status_change, and fn_post_verification_cascade can be invoked
-- directly via /rest/v1/rpc/<name> by anon and authenticated roles.
-- They are meant to fire only as triggers, never as user RPCs.
-- Revoking EXECUTE removes them from the REST surface; triggers still work
-- because PostgreSQL invokes trigger functions internally regardless of
-- granted privileges (and they are SECURITY DEFINER as well, so they keep
-- running with the table owner's permissions).
--
-- Also pin search_path on fn_validate_birth_record_status, which is a
-- SECURITY INVOKER function but should still have a stable search_path.

revoke execute on function public.fn_audit_trail()                from anon, authenticated, public;
revoke execute on function public.fn_log_status_change()           from anon, authenticated, public;
revoke execute on function public.fn_post_verification_cascade()   from anon, authenticated, public;

alter function public.fn_validate_birth_record_status()
  set search_path = public;
