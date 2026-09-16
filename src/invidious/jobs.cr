module Invidious::Jobs
  JOBS = [] of BaseJob

  # Automatically generate a structure that wraps the various
  # jobs' configs, so that the following YAML config can be used:
  #
  # jobs:
  #   job_name:
  #     enabled: true
  #     some_property: "value"
  #
  macro finished
    struct JobsConfig
      include YAML::Serializable

      {% for sc in BaseJob.subclasses %}
        # Voodoo macro to transform `Some::Module::CustomJob` to `custom`
        {% class_name = sc.id.split("::").last.id.gsub(/Job$/, "").underscore %}

        getter {{ class_name }} = {{ sc.name }}::Config.new
      {% end %}

      def initialize
      end
    end
  end

  def self.register(job : BaseJob)
    JOBS << job
  end

  # Delay before a crashed job is restarted; doubles up to MAX_RESTART_DELAY.
  INITIAL_RESTART_DELAY = 5.seconds
  MAX_RESTART_DELAY     = 10.minutes

  def self.start_all
    JOBS.each do |job|
      # Don't run the main rountine if the job is disabled by config
      next if job.disabled?

      spawn { supervise(job) }
    end
  end

  # Runs `job.begin` and restarts it with exponential backoff if it raises.
  # A job's main loop is expected to run forever; if it returns, that is
  # treated like a crash as well.
  def self.supervise(job : BaseJob)
    delay = INITIAL_RESTART_DELAY

    loop do
      begin
        job.begin
        LOGGER.error("jobs: #{job.class.name} returned unexpectedly, restarting in #{delay}")
      rescue ex
        LOGGER.error("jobs: #{job.class.name} crashed: #{ex.class}: #{ex.message}, restarting in #{delay}")
      end

      sleep delay
      delay = {delay * 2, MAX_RESTART_DELAY}.min
    end
  end
end
