
update public.brand_catalog
   set patterns = array['playstation plus', 'ps plus', 'psn plus']
 where brand_name = 'PlayStation Plus';

update public.brand_catalog
   set patterns = array['xbox game pass', 'game pass']
 where brand_name = 'Xbox Game Pass';

update public.brand_catalog
   set patterns = array['nintendo switch online', 'switch online']
 where brand_name = 'Nintendo Switch Online';

insert into public.brand_catalog (brand_name, domain, category, subscription_only, patterns, kind)
values
  ('PlayStation', 'playstation.com', 'Games', false, array['playstation', 'psn', 'sony playstation'], 'service'),
  ('Xbox',        'xbox.com',        'Games', false, array['xbox', 'microsoft xbox'],                 'service'),
  ('Nintendo',    'nintendo.com',    'Games', false, array['nintendo', 'nintendo eshop'],             'service');
