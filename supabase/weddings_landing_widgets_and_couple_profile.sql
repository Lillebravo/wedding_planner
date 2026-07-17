-- Landing page widget visibility + couple profile columns
alter table weddings
  add column if not exists show_meet_couple boolean not null default true,
  add column if not exists show_countdown boolean not null default true,
  add column if not exists show_details boolean not null default true,
  add column if not exists show_itinerary boolean not null default true,
  add column if not exists show_hero_text boolean not null default true,
  add column if not exists partner1_description text not null default '',
  add column if not exists partner2_description text not null default '',
  add column if not exists partner1_image_url text,
  add column if not exists partner2_image_url text;
