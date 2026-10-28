-- École Privée Les Étoiles: admin-only maintenance permissions
-- Apply once to the school's Supabase project. No data is deleted.
ALTER TABLE public.subjects
  ADD COLUMN IF NOT EXISTS weekly_hours numeric(4,1)
  CHECK (weekly_hours IS NULL OR (weekly_hours >= 0 AND weekly_hours <= 60));

CREATE OR REPLACE FUNCTION public.is_school_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.user_id = auth.uid()
      AND lower(p.role) = 'admin'
  );
$$;

REVOKE ALL ON FUNCTION public.is_school_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_school_admin() TO authenticated;

ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;

-- Permissive admin policies allow authorized writes.
DROP POLICY IF EXISTS school_admin_insert_students ON public.students;
CREATE POLICY school_admin_insert_students ON public.students
  FOR INSERT TO authenticated WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_update_students ON public.students;
CREATE POLICY school_admin_update_students ON public.students
  FOR UPDATE TO authenticated USING (public.is_school_admin()) WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_delete_students ON public.students;
CREATE POLICY school_admin_delete_students ON public.students
  FOR DELETE TO authenticated USING (public.is_school_admin());

DROP POLICY IF EXISTS school_admin_insert_staff ON public.staff;
CREATE POLICY school_admin_insert_staff ON public.staff
  FOR INSERT TO authenticated WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_update_staff ON public.staff;
CREATE POLICY school_admin_update_staff ON public.staff
  FOR UPDATE TO authenticated USING (public.is_school_admin()) WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_delete_staff ON public.staff;
CREATE POLICY school_admin_delete_staff ON public.staff
  FOR DELETE TO authenticated USING (public.is_school_admin());

DROP POLICY IF EXISTS school_admin_insert_subjects ON public.subjects;
CREATE POLICY school_admin_insert_subjects ON public.subjects
  FOR INSERT TO authenticated WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_update_subjects ON public.subjects;
CREATE POLICY school_admin_update_subjects ON public.subjects
  FOR UPDATE TO authenticated USING (public.is_school_admin()) WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_delete_subjects ON public.subjects;
CREATE POLICY school_admin_delete_subjects ON public.subjects
  FOR DELETE TO authenticated USING (public.is_school_admin());

-- Restrictive policies ensure an older broad write policy cannot grant
-- students/personnel non-admin users permission to alter these records.
DROP POLICY IF EXISTS school_admin_only_insert_students ON public.students;
CREATE POLICY school_admin_only_insert_students ON public.students
  AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_only_update_students ON public.students;
CREATE POLICY school_admin_only_update_students ON public.students
  AS RESTRICTIVE FOR UPDATE TO authenticated USING (public.is_school_admin()) WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_only_delete_students ON public.students;
CREATE POLICY school_admin_only_delete_students ON public.students
  AS RESTRICTIVE FOR DELETE TO authenticated USING (public.is_school_admin());

DROP POLICY IF EXISTS school_admin_only_insert_staff ON public.staff;
CREATE POLICY school_admin_only_insert_staff ON public.staff
  AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_only_update_staff ON public.staff;
CREATE POLICY school_admin_only_update_staff ON public.staff
  AS RESTRICTIVE FOR UPDATE TO authenticated USING (public.is_school_admin()) WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_only_delete_staff ON public.staff;
CREATE POLICY school_admin_only_delete_staff ON public.staff
  AS RESTRICTIVE FOR DELETE TO authenticated USING (public.is_school_admin());

DROP POLICY IF EXISTS school_admin_only_insert_subjects ON public.subjects;
CREATE POLICY school_admin_only_insert_subjects ON public.subjects
  AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_only_update_subjects ON public.subjects;
CREATE POLICY school_admin_only_update_subjects ON public.subjects
  AS RESTRICTIVE FOR UPDATE TO authenticated USING (public.is_school_admin()) WITH CHECK (public.is_school_admin());
DROP POLICY IF EXISTS school_admin_only_delete_subjects ON public.subjects;
CREATE POLICY school_admin_only_delete_subjects ON public.subjects
  AS RESTRICTIVE FOR DELETE TO authenticated USING (public.is_school_admin());
