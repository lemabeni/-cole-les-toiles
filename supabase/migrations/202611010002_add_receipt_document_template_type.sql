-- Allow administrators to save customizable payment receipt templates.
-- Existing Bulletin, Certificat and Attestation templates remain valid.
alter table public.document_templates
  drop constraint if exists document_templates_document_type_check;

alter table public.document_templates
  add constraint document_templates_document_type_check
  check (document_type = any (array['Bulletin'::text, 'Certificat'::text, 'Attestation'::text, 'Reçu'::text]));
