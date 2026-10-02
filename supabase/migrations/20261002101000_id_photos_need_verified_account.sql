-- Only a verified account can upload an ID photo or file a discount claim
-- (release audit, 2 Oct 2026).
--
-- sweep_abandoned_registrations() and abandon_unverified_registration() delete
-- an account from SQL, where Storage cannot be cleaned. An account that never
-- verified its number could still upload a photo of someone's ID; when it was
-- swept two hours later the photo stayed in the bucket for good, with nothing
-- left that named it. (Accounts deleted through the account-deletion function
-- have their files removed there.)
--
-- The app only shows the discount screen after phone verification, so no
-- screen changes. is_verified_account() also passes internal testers, which
-- the sweep never deletes.
alter policy discount_id_insert_own on storage.objects
  with check (
    bucket_id = 'discount-eligibility-ids'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.is_verified_account((select auth.uid()))
  );

do $$
declare
  v_func constant regprocedure := 'public.submit_fare_class_claim(text,text)'::regprocedure;
  v_anchor constant text := 'select * into v_claimant from public.profiles where id = auth.uid();';
  v_definition text := pg_get_functiondef(v_func);
begin
  if (length(v_definition) - length(replace(v_definition, v_anchor, '')))
     <> length(v_anchor) then
    raise exception 'submit_fare_class_claim changed; review the ID photo migration';
  end if;
  execute replace(v_definition, v_anchor, v_anchor || '

  if not public.is_verified_account(auth.uid()) then
    raise exception ''verify your mobile number before claiming a discount''
      using errcode = ''42501'';
  end if;');
end;
$$;
