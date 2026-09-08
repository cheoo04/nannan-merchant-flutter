-- Sort les stories du tableau merchants.story_images / story_video_url
-- vers une vraie table, pour permettre une description par publication.

create type story_media_type as enum ('image', 'video');

create table merchant_stories (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants(id) on delete cascade,
  media_type story_media_type not null,
  media_url text not null,
  description text,
  position int not null default 0,
  created_at timestamptz not null default now()
);

create index idx_merchant_stories_merchant on merchant_stories(merchant_id, position);

alter table merchant_stories enable row level security;

create policy "owner manages own stories" on merchant_stories
  for all using (
    exists (select 1 from merchants m
            where m.id = merchant_stories.merchant_id and m.owner_id = auth.uid())
  );

create policy "anyone views stories of active merchants" on merchant_stories
  for select using (
    exists (select 1 from merchants m
            where m.id = merchant_stories.merchant_id and m.status = 'active')
  );

-- Migration des données existantes (tableau -> lignes)
insert into merchant_stories (merchant_id, media_type, media_url, position)
select id, 'image', unnest(story_images), generate_subscripts(story_images, 1) - 1
from merchants
where story_images is not null and array_length(story_images, 1) > 0;

insert into merchant_stories (merchant_id, media_type, media_url, position)
select id, 'video', story_video_url, 999
from merchants
where story_video_url is not null;

-- story_images / story_video_url gardées sur merchants pendant la transition
-- (à retirer une fois que l'app Client aura basculé sa lecture sur merchant_stories)
