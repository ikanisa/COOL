-- The app uses REST/RPC APIs only. Keep GraphQL introspection explicitly off
-- so schema enumeration stays disabled in production even if defaults change.
comment on schema public is e'@graphql({"introspection": false})';
