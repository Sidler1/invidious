class Invidious::Jobs::RefreshChannelsJob < Invidious::Jobs::BaseJob
  private INITIAL_BACKOFF = 2.minutes
  private MAX_BACKOFF     = 30.minutes

  private getter db : DB::Database

  def initialize(@db)
  end

  def begin
    max_fibers = CONFIG.channel_threads
    active_fibers = 0
    active_channel = ::Channel(Bool).new

    loop do
      backoff = INITIAL_BACKOFF
      LOGGER.debug("RefreshChannelsJob: Refreshing all channels")
      begin
        ids = PG_DB.query_all("SELECT id FROM channels WHERE deleted IS NOT TRUE ORDER BY updated", as: String)
        ids.each do |id|
          if active_fibers >= max_fibers
            LOGGER.trace("RefreshChannelsJob: Fiber limit reached, waiting...")
            if active_channel.receive
              LOGGER.trace("RefreshChannelsJob: Fiber limit ok, continuing")
              active_fibers -= 1
            end
          end

          LOGGER.debug("RefreshChannelsJob: #{id} : Spawning fiber")
          active_fibers += 1
          spawn do
            begin
              LOGGER.trace("RefreshChannelsJob: #{id} fiber : Fetching channel")
              channel = fetch_channel(id, pull_all_videos: CONFIG.full_refresh)

              LOGGER.trace("RefreshChannelsJob: #{id} fiber : Updating DB")
              Invidious::Database::Channels.update_author(id, channel.author)

              if backoff > INITIAL_BACKOFF
                backoff /= 2
                LOGGER.debug("RefreshChannelsJob: #{id} fiber : decreasing backoff to #{backoff}")
              end
            rescue ex
              LOGGER.error("RefreshChannelsJob: #{id} : #{ex.message}")
              if ex.message == "Deleted or invalid channel"
                Invidious::Database::Channels.update_mark_deleted(id)
              else
                LOGGER.error("RefreshChannelsJob: #{id} fiber : backing off for #{backoff}")
                sleep backoff
                backoff = {backoff * 2, MAX_BACKOFF}.min
              end
            ensure
              LOGGER.debug("RefreshChannelsJob: #{id} fiber : Done")
              active_channel.send(true)
            end
          end
        end
      rescue ex
        LOGGER.error("RefreshChannelsJob: #{ex.message}")
      end

      LOGGER.debug("RefreshChannelsJob: Done, sleeping for #{CONFIG.channel_refresh_interval}")
      sleep CONFIG.channel_refresh_interval
      Fiber.yield
    end
  end
end
