begin;

-- Keep runtime metadata SELECT policies single-purpose so Supabase's planner
-- does not evaluate duplicate permissive policies for authenticated reads.

drop policy if exists "collection type catalog public enabled read" on public.collection_type_catalog;
drop policy if exists "collection type catalog admin manage" on public.collection_type_catalog;
create policy "collection type catalog public enabled read"
on public.collection_type_catalog for select to anon
using (enabled);
create policy "collection type catalog authenticated read"
on public.collection_type_catalog for select to authenticated
using (
  enabled
  or public.has_admin_permission('settings.manage', (select auth.uid()))
);
create policy "collection type catalog admin insert"
on public.collection_type_catalog for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "collection type catalog admin update"
on public.collection_type_catalog for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "collection type catalog admin delete"
on public.collection_type_catalog for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "collection category subtypes public enabled read" on public.collection_category_subtypes;
drop policy if exists "collection category subtypes admin manage" on public.collection_category_subtypes;
create policy "collection category subtypes public enabled read"
on public.collection_category_subtypes for select to anon
using (
  enabled
  and exists (
    select 1
    from public.collection_type_catalog ctc
    where ctc.key = collection_category_subtypes.collection_type_key
      and ctc.enabled
  )
);
create policy "collection category subtypes authenticated read"
on public.collection_category_subtypes for select to authenticated
using (
  (
    enabled
    and exists (
      select 1
      from public.collection_type_catalog ctc
      where ctc.key = collection_category_subtypes.collection_type_key
        and ctc.enabled
    )
  )
  or public.has_admin_permission('settings.manage', (select auth.uid()))
);
create policy "collection category subtypes admin insert"
on public.collection_category_subtypes for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "collection category subtypes admin update"
on public.collection_category_subtypes for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "collection category subtypes admin delete"
on public.collection_category_subtypes for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "collection purpose templates public enabled read" on public.collection_purpose_templates;
drop policy if exists "collection purpose templates admin manage" on public.collection_purpose_templates;
create policy "collection purpose templates public enabled read"
on public.collection_purpose_templates for select to anon
using (
  enabled
  and exists (
    select 1
    from public.collection_type_catalog ctc
    where ctc.key = collection_purpose_templates.collection_type_key
      and ctc.enabled
  )
);
create policy "collection purpose templates authenticated read"
on public.collection_purpose_templates for select to authenticated
using (
  (
    enabled
    and exists (
      select 1
      from public.collection_type_catalog ctc
      where ctc.key = collection_purpose_templates.collection_type_key
        and ctc.enabled
    )
  )
  or public.has_admin_permission('settings.manage', (select auth.uid()))
);
create policy "collection purpose templates admin insert"
on public.collection_purpose_templates for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "collection purpose templates admin update"
on public.collection_purpose_templates for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "collection purpose templates admin delete"
on public.collection_purpose_templates for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "collection type country rules public enabled read" on public.collection_type_country_rules;
drop policy if exists "collection type country rules admin manage" on public.collection_type_country_rules;
create policy "collection type country rules public enabled read"
on public.collection_type_country_rules for select to anon
using (
  enabled
  and exists (
    select 1
    from public.collection_type_catalog ctc
    where ctc.key = collection_type_country_rules.collection_type_key
      and ctc.enabled
  )
);
create policy "collection type country rules authenticated read"
on public.collection_type_country_rules for select to authenticated
using (
  (
    enabled
    and exists (
      select 1
      from public.collection_type_catalog ctc
      where ctc.key = collection_type_country_rules.collection_type_key
        and ctc.enabled
    )
  )
  or public.has_admin_permission('settings.manage', (select auth.uid()))
);
create policy "collection type country rules admin insert"
on public.collection_type_country_rules for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "collection type country rules admin update"
on public.collection_type_country_rules for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "collection type country rules admin delete"
on public.collection_type_country_rules for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "notification channels public enabled read" on public.notification_channels;
drop policy if exists "notification channels admin manage" on public.notification_channels;
create policy "notification channels public enabled read"
on public.notification_channels for select to anon
using (enabled);
create policy "notification channels authenticated read"
on public.notification_channels for select to authenticated
using (
  enabled
  or public.has_admin_permission('settings.manage', (select auth.uid()))
);
create policy "notification channels admin insert"
on public.notification_channels for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "notification channels admin update"
on public.notification_channels for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "notification channels admin delete"
on public.notification_channels for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "notification event types public enabled read" on public.notification_event_types;
drop policy if exists "notification event types admin manage" on public.notification_event_types;
create policy "notification event types public enabled read"
on public.notification_event_types for select to anon
using (enabled);
create policy "notification event types authenticated read"
on public.notification_event_types for select to authenticated
using (
  enabled
  or public.has_admin_permission('settings.manage', (select auth.uid()))
);
create policy "notification event types admin insert"
on public.notification_event_types for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "notification event types admin update"
on public.notification_event_types for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "notification event types admin delete"
on public.notification_event_types for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "notification templates public enabled read" on public.notification_templates;
drop policy if exists "notification templates admin manage" on public.notification_templates;
create policy "notification templates public enabled read"
on public.notification_templates for select to anon
using (
  enabled
  and exists (
    select 1
    from public.notification_event_types net
    where net.key = notification_templates.event_type_key
      and net.enabled
  )
);
create policy "notification templates authenticated read"
on public.notification_templates for select to authenticated
using (
  (
    enabled
    and exists (
      select 1
      from public.notification_event_types net
      where net.key = notification_templates.event_type_key
        and net.enabled
    )
  )
  or public.has_admin_permission('settings.manage', (select auth.uid()))
);
create policy "notification templates admin insert"
on public.notification_templates for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "notification templates admin update"
on public.notification_templates for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "notification templates admin delete"
on public.notification_templates for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "notification template versions public published read" on public.notification_template_versions;
drop policy if exists "notification template versions admin manage" on public.notification_template_versions;
create policy "notification template versions public published read"
on public.notification_template_versions for select to anon
using (
  status = 'published'
  and effective_at <= now()
  and exists (
    select 1
    from public.notification_templates nt
    join public.notification_event_types net on net.key = nt.event_type_key
    where nt.key = notification_template_versions.template_key
      and nt.enabled
      and net.enabled
  )
);
create policy "notification template versions authenticated read"
on public.notification_template_versions for select to authenticated
using (
  (
    status = 'published'
    and effective_at <= now()
    and exists (
      select 1
      from public.notification_templates nt
      join public.notification_event_types net on net.key = nt.event_type_key
      where nt.key = notification_template_versions.template_key
        and nt.enabled
        and net.enabled
    )
  )
  or public.has_admin_permission('settings.manage', (select auth.uid()))
);
create policy "notification template versions admin insert"
on public.notification_template_versions for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "notification template versions admin update"
on public.notification_template_versions for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "notification template versions admin delete"
on public.notification_template_versions for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "brand entities public read active" on public.brand_entities;
drop policy if exists "brand entities admin read all" on public.brand_entities;
create policy "brand entities public read active"
on public.brand_entities for select to anon
using (is_active);
create policy "brand entities authenticated read"
on public.brand_entities for select to authenticated
using (
  is_active
  or public.has_admin_permission('settings.read', (select auth.uid()))
);

drop policy if exists "support channels public read active" on public.support_channels;
drop policy if exists "support channels admin read all" on public.support_channels;
create policy "support channels public read active"
on public.support_channels for select to anon
using (is_active);
create policy "support channels authenticated read"
on public.support_channels for select to authenticated
using (
  is_active
  or public.has_admin_permission('settings.read', (select auth.uid()))
);

drop policy if exists "payment entrypoints public read active" on public.payment_entrypoints;
drop policy if exists "payment entrypoints admin read all" on public.payment_entrypoints;
create policy "payment entrypoints public read active"
on public.payment_entrypoints for select to anon
using (is_active);
create policy "payment entrypoints authenticated read"
on public.payment_entrypoints for select to authenticated
using (
  is_active
  or public.has_admin_permission('settings.read', (select auth.uid()))
);

drop policy if exists "admin navigation manage admins" on public.admin_navigation_items;
create policy "admin navigation insert admins"
on public.admin_navigation_items for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "admin navigation update admins"
on public.admin_navigation_items for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "admin navigation delete admins"
on public.admin_navigation_items for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "admin queue specs manage admins" on public.admin_queue_specs;
create policy "admin queue specs insert admins"
on public.admin_queue_specs for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "admin queue specs update admins"
on public.admin_queue_specs for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "admin queue specs delete admins"
on public.admin_queue_specs for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "admin queue filter options manage admins" on public.admin_queue_filter_options;
create policy "admin queue filter options insert admins"
on public.admin_queue_filter_options for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "admin queue filter options update admins"
on public.admin_queue_filter_options for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "admin queue filter options delete admins"
on public.admin_queue_filter_options for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "admin queue signals manage admins" on public.admin_queue_signals;
create policy "admin queue signals insert admins"
on public.admin_queue_signals for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "admin queue signals update admins"
on public.admin_queue_signals for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "admin queue signals delete admins"
on public.admin_queue_signals for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "policy documents public published read" on public.policy_documents;
drop policy if exists "policy documents admin manage" on public.policy_documents;
create policy "policy documents public published read"
on public.policy_documents for select to anon
using (status = 'published' and effective_at <= now());
create policy "policy documents authenticated read"
on public.policy_documents for select to authenticated
using (
  (status = 'published' and effective_at <= now())
  or public.has_admin_permission('settings.manage', (select auth.uid()))
);
create policy "policy documents admin insert"
on public.policy_documents for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "policy documents admin update"
on public.policy_documents for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "policy documents admin delete"
on public.policy_documents for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "policy sections public published read" on public.policy_document_sections;
drop policy if exists "policy sections admin manage" on public.policy_document_sections;
create policy "policy sections public published read"
on public.policy_document_sections for select to anon
using (
  exists (
    select 1
    from public.policy_documents pd
    where pd.id = policy_document_sections.policy_document_id
      and pd.status = 'published'
      and pd.effective_at <= now()
  )
);
create policy "policy sections authenticated read"
on public.policy_document_sections for select to authenticated
using (
  exists (
    select 1
    from public.policy_documents pd
    where pd.id = policy_document_sections.policy_document_id
      and (
        (pd.status = 'published' and pd.effective_at <= now())
        or public.has_admin_permission('settings.manage', (select auth.uid()))
      )
  )
);
create policy "policy sections admin insert"
on public.policy_document_sections for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "policy sections admin update"
on public.policy_document_sections for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "policy sections admin delete"
on public.policy_document_sections for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

drop policy if exists "account request reasons public enabled read" on public.account_request_reason_options;
drop policy if exists "account request reasons admin manage" on public.account_request_reason_options;
create policy "account request reasons public enabled read"
on public.account_request_reason_options for select to anon
using (enabled);
create policy "account request reasons authenticated read"
on public.account_request_reason_options for select to authenticated
using (
  enabled
  or public.has_admin_permission('settings.manage', (select auth.uid()))
);
create policy "account request reasons admin insert"
on public.account_request_reason_options for insert to authenticated
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "account request reasons admin update"
on public.account_request_reason_options for update to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())))
with check (public.has_admin_permission('settings.manage', (select auth.uid())));
create policy "account request reasons admin delete"
on public.account_request_reason_options for delete to authenticated
using (public.has_admin_permission('settings.manage', (select auth.uid())));

commit;
