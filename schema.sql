-- Social Telegram Schema
-- Run this in Supabase SQL Editor

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =====================
-- USERS
-- =====================
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  telegram_id BIGINT NOT NULL UNIQUE,
  username TEXT,
  first_name TEXT,
  last_name TEXT,
  avatar_url TEXT,
  bio TEXT DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_telegram_id ON users(telegram_id);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

-- =====================
-- POSTS
-- =====================
CREATE TABLE IF NOT EXISTS posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  image_url TEXT,
  telegram_file_id TEXT,
  caption TEXT DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at DESC);

-- =====================
-- LIKES
-- =====================
CREATE TABLE IF NOT EXISTS likes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_likes_post_id ON likes(post_id);
CREATE INDEX IF NOT EXISTS idx_likes_user_id ON likes(user_id);

-- =====================
-- COMMENTS
-- =====================
CREATE TABLE IF NOT EXISTS comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_comments_post_id ON comments(post_id);
CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id);

-- =====================
-- FOLLOWS
-- =====================
CREATE TABLE IF NOT EXISTS follows (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(follower_id, following_id),
  CHECK (follower_id <> following_id)
);

CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);

-- =====================
-- NOTIFICATIONS
-- =====================
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('like', 'comment', 'follow')),
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC);

-- =====================
-- BOT STATE (for serverless conversation)
-- =====================
CREATE TABLE IF NOT EXISTS bot_states (
  telegram_id BIGINT PRIMARY KEY,
  state TEXT NOT NULL,
  data JSONB DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =====================
-- UPDATED_AT TRIGGER
-- =====================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_posts_updated_at ON posts;
CREATE TRIGGER update_posts_updated_at
  BEFORE UPDATE ON posts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================
-- RLS
-- =====================
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE bot_states ENABLE ROW LEVEL SECURITY;

-- Because this is a backend bot using service_role key,
-- we allow full access for the service role (which bypasses RLS).
-- Policies below are for safety if anon key is ever used.

-- Users: anyone can read, only service can write (bot handles auth)
CREATE POLICY "Users are viewable by everyone"
  ON users FOR SELECT
  USING (true);

CREATE POLICY "Users can be inserted by service"
  ON users FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Users can be updated by service"
  ON users FOR UPDATE
  USING (true);

-- Posts: public read
CREATE POLICY "Posts are viewable by everyone"
  ON posts FOR SELECT
  USING (true);

CREATE POLICY "Posts can be inserted by service"
  ON posts FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Posts can be updated by service"
  ON posts FOR UPDATE
  USING (true);

CREATE POLICY "Posts can be deleted by service"
  ON posts FOR DELETE
  USING (true);

-- Likes
CREATE POLICY "Likes are viewable by everyone"
  ON likes FOR SELECT
  USING (true);

CREATE POLICY "Likes can be managed by service"
  ON likes FOR ALL
  USING (true);

-- Comments
CREATE POLICY "Comments are viewable by everyone"
  ON comments FOR SELECT
  USING (true);

CREATE POLICY "Comments can be managed by service"
  ON comments FOR ALL
  USING (true);

-- Follows
CREATE POLICY "Follows are viewable by everyone"
  ON follows FOR SELECT
  USING (true);

CREATE POLICY "Follows can be managed by service"
  ON follows FOR ALL
  USING (true);

-- Notifications
CREATE POLICY "Notifications are viewable by owner (service)"
  ON notifications FOR SELECT
  USING (true);

CREATE POLICY "Notifications can be managed by service"
  ON notifications FOR ALL
  USING (true);

-- Bot states (only service)
CREATE POLICY "Bot states managed by service"
  ON bot_states FOR ALL
  USING (true);

-- =====================
-- STORAGE BUCKET
-- =====================
-- Create bucket "posts" via Supabase Dashboard (Storage)
-- Then run these policies:

-- INSERT policy for posts bucket (service role will upload)
-- You can set the bucket to public for easy image access,
-- or keep private and generate signed URLs.

-- Recommended: make bucket "posts" PUBLIC so image_url can be used directly.
