begin;
      insert into public.notification_event_types(key,preference_key,label,description,default_channel_key,display_order,enabled)
        values('group_update','group_updates','Group update','A group profile, member, or status changed.','collect_group_updates',30,true);
      insert into public.notification_templates(key,event_type_key,locale,enabled)
        values('group.update.default','group_update','en',true);
      insert into public.notification_template_versions(template_key,version,title_template,body_template,status,effective_at,published_at)
        values('group.update.default','2026-07-04','Group update','{{group}} has a new update.','published',
          '2026-07-04 00:00:00+00','2026-07-04 00:00:00+00');commit;