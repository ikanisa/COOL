revoke execute on function admin_list_payment_events(text, text, integer, integer, text)
from public, anon;

revoke execute on function admin_list_allocations(text, text, integer, integer, text)
from public, anon;

revoke execute on function admin_list_unallocated(text, text, integer, integer, text)
from public, anon;

grant execute on function admin_list_payment_events(text, text, integer, integer, text)
to authenticated;

grant execute on function admin_list_allocations(text, text, integer, integer, text)
to authenticated;

grant execute on function admin_list_unallocated(text, text, integer, integer, text)
to authenticated;
