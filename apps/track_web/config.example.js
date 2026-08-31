// Copy to config.js and fill in. config.js is gitignored.
//
// Everything here ships to the browser and is readable by anyone who opens a
// tracking link. That is expected -- none of it is a secret:
//
//   supabaseAnonKey  Designed for clients. RLS is what protects the data, and
//                    ride_share_links denies anon outright. The ONLY thing anon
//                    can execute is ride_share_view(), which returns a
//                    hand-written column list for one active trip.
//
//   maptiler key     Client-side by design. The control is NOT secrecy, it is
//                    the domain restriction: lock the key to arangcada.app in
//                    the MapTiler dashboard. A public web page is more exposed
//                    than an APK, so this restriction is not optional.
//
// A service_role key must NEVER appear in this file. There is deliberately no
// variable name reserved for one.

window.ARANGCADA_CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT_REF.supabase.co',
  supabaseAnonKey: 'YOUR_SUPABASE_ANON_KEY',
  mapStyleUrl: 'https://api.maptiler.com/maps/streets-v2/style.json?key=YOUR_MAPTILER_KEY',
};
