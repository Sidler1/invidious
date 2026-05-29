class Invidious::Jobs::PullPopularVideosJob < Invidious::Jobs::BaseJob
  POPULAR_VIDEOS = Atomic.new([] of ChannelVideo)
  private getter db : DB::Database

  def initialize(@db)
  end

  def begin
    loop do
      begin
        videos = Invidious::Database::ChannelVideos.select_popular_videos
          .sort_by!(&.published)
          .reverse!

        POPULAR_VIDEOS.set(videos)
      rescue ex
        LOGGER.error("PullPopularVideosJob: #{ex.message}")
      end

      sleep 1.minute
      Fiber.yield
    end
  end
end
