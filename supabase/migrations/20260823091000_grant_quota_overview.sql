-- The overview view is read by the admin console through PostgREST, which needs
-- both a grant and a cache reload before it can see a newly created view.
--
-- service_role only: these rows say what every membership level allows and how
-- many people are on each, which is administrator information rather than
-- something a signed-in user should be able to read.

grant select on public.ai_quota_overview to service_role;
grant select, update on public.ai_quota_tiers to service_role;
grant select, update on public.ai_quota_settings to service_role;

notify pgrst, 'reload schema';
