-- Starter opportunity records. Verify each official page before advising a student.
-- Dates are intentionally NULL when the organizer has not published a concrete deadline.
insert into public.opportunities
  (title,kind,country,eligible_regions,grade_min,grade_max,field,cost_kzt,funding,deadline,url,source_name,checked_at,status)
select v.title,v.kind,v.country,v.eligible_regions,v.grade_min,v.grade_max,v.field,v.cost_kzt,v.funding,v.deadline,v.url,v.source_name,date '2026-11-14','published'
from (values
  ('FLEX Global · набор 2027–28','summer_program','United States',array['Kazakhstan']::text[],9,11,'exchange and language',null::numeric,'Program-funded; confirm current country details',null::date,'https://www.discoverflexglobal.org/apply-to-flex','FLEX Global / U.S. Department of State'),
  ('FIRST Kazakhstan · сезон 2026–27','competition','Kazakhstan',array['Kazakhstan']::text[],5,12,'robotics and STEM',null::numeric,'Ask local team about participation costs',null::date,'https://firstrobotics.kz/','FIRST Kazakhstan / USTEM Foundation'),
  ('Alem Tech Fest · 2027','event','Kazakhstan',array['Kazakhstan']::text[],7,12,'technology, engineering and AI',null::numeric,'Organizer terms to be checked',null::date,'https://ustem.kz/ru','USTEM Foundation'),
  ('Almaty Tech Cup · 2027','competition','Kazakhstan',array['Kazakhstan']::text[],7,12,'robotics, engineering and AI',null::numeric,'Organizer terms to be checked',null::date,'https://ustem.kz/ru','USTEM Foundation'),
  ('Nazarbayev University · undergraduate admissions','other','Kazakhstan',array['Kazakhstan','International']::text[],11,12,'undergraduate admissions',null::numeric,'Scholarship and tuition terms depend on the program',null::date,'https://admissions.nu.edu.kz/','Nazarbayev University Admissions'),
  ('Olympiads and competitions · Daryn','olympiad','Kazakhstan',array['Kazakhstan']::text[],7,12,'school subjects and science',null::numeric,'See each official competition notice',null::date,'https://daryn.kz/','Republican Scientific and Practical Center Daryn'),
  ('World Robot Olympiad Kazakhstan','olympiad','Kazakhstan',array['Kazakhstan']::text[],5,12,'robotics',null::numeric,'Confirm current season and team fees',null::date,'https://robotics.nis.edu.kz/en','NIS Robotics · Kazakhstan national organizer'),
  ('Astana Hub events for students','other','Kazakhstan',array['Kazakhstan']::text[],7,12,'startups, digital projects and AI',null::numeric,'Depends on each event',null::date,'https://astanahub.com/ru/event/','Astana Hub events calendar')
) as v(title,kind,country,eligible_regions,grade_min,grade_max,field,cost_kzt,funding,deadline,url,source_name)
where not exists (select 1 from public.opportunities o where o.url=v.url and o.title=v.title);
