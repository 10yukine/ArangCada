-- Size and type limits for the three photo buckets (release audit, 2 Oct 2026).
--
-- Only trip-voice-notes had limits. The other three took a file of any size
-- and any type from any signed-in account into its own folder.
--
-- Every upload the apps make is a photo from the image picker, and the Storage
-- client sends the content type that matches the file extension, so image/*
-- covers them. Profile photos are cropped to 1200 px and ID photos scaled to
-- 1600 px before upload; driver documents are scaled to 2000 px and can be
-- PNG, hence the larger limit. Limits apply to new uploads only.
update storage.buckets
   set file_size_limit = 5 * 1024 * 1024, allowed_mime_types = array['image/*']
 where id in ('profile-photos', 'discount-eligibility-ids');

update storage.buckets
   set file_size_limit = 10 * 1024 * 1024, allowed_mime_types = array['image/*']
 where id = 'driver-documents';

-- admin_upsert_driver_document recorded whatever path it was given, so a
-- scoped admin could point one driver's document at another driver's file.
-- The console always uploads to {driver_id}/..., which is also the only shape
-- the driver app will open.
do $$
declare
  v_func constant regprocedure :=
    'public.admin_upsert_driver_document(uuid,public.document_type,text)'::regprocedure;
  v_anchor constant text :=
    'insert into public.driver_documents (driver_id, document_type, storage_path, status)';
  v_definition text := pg_get_functiondef(v_func);
begin
  if (length(v_definition) - length(replace(v_definition, v_anchor, '')))
     <> length(v_anchor) then
    raise exception 'admin_upsert_driver_document changed; review the upload limits migration';
  end if;
  execute replace(v_definition, v_anchor,
    'if p_storage_path is null
     or left(p_storage_path, 37) <> p_driver_id::text || ''/''
     or p_storage_path like ''%..%'' then
    raise exception ''a driver document must be stored in that driver''''s own folder''
      using errcode = ''22023'';
  end if;

  ' || v_anchor);
end;
$$;
