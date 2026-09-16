module Invidious::Database::Migrations
  class AddHotPathIndexes < Migration
    version 11

    def up(conn : DB::Connection)
      # /feed/private looks users up by token on every RSS poll
      conn.exec "CREATE INDEX IF NOT EXISTS users_token_idx ON public.users (token)"
      # `subscriptions @> ARRAY[ucid]` in notification and feed updates
      conn.exec "CREATE INDEX IF NOT EXISTS users_subscriptions_gin_idx ON public.users USING gin (subscriptions)"
      # RefreshFeedsJob polls this predicate every few seconds
      conn.exec "CREATE INDEX IF NOT EXISTS users_feed_needs_update_idx ON public.users (email) WHERE feed_needs_update = true OR feed_needs_update IS NULL"
      # playlists by author are listed on /watch and /feed/playlists
      conn.exec "CREATE INDEX IF NOT EXISTS playlists_author_idx ON public.playlists (author)"
      # playlist_videos primary key is (index, plid); lookups are by plid
      conn.exec "CREATE INDEX IF NOT EXISTS playlist_videos_plid_idx ON public.playlist_videos (plid)"
    end
  end
end
