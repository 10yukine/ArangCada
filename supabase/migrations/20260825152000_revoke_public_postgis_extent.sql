-- These PostGIS helper overloads are not part of the app API.
revoke execute on function public.st_estimatedextent(text, text) from public;
revoke execute on function public.st_estimatedextent(text, text, text) from public;
revoke execute on function public.st_estimatedextent(text, text, text, boolean) from public;
