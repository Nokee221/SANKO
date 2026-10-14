-- Postavlja superadmina (prodavca) kao poseban nalog, odvojen od gazdi kafića.
-- Prije pokretanja: napravite nalog u Authentication -> Users -> Add user
-- (npr. superadmin@sanko.ba, sa svojom lozinkom) i upišite taj e-mail ispod.

-- Gazda kafića Korzo više nije superadmin.
delete from private.vendor_admins v
using auth.users u
where u.id = v.user_id and lower(u.email) = 'cosabrat6@gmail.com';

-- Novi superadmin.
insert into private.vendor_admins (user_id)
select u.id from auth.users u
where lower(u.email) = lower('superadmin@sanko.ba')
on conflict do nothing;

-- Provjera: treba ispisati samo novi e-mail.
select u.email as superadmin
from private.vendor_admins v
join auth.users u on u.id = v.user_id;
