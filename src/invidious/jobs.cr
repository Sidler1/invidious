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
  # Everything derived from a job's class name is generated here, from the
  # same expression, so the `jobs:` key a job is configured under, the key
  # `apply_config` copies from and the name the startup warning prints can
  # never drift apart.
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

    # Copies a job's slice of the `jobs:` section onto the job itself.
    # Without this a job keeps the default `Config.new` it was constructed
    # with, and `enable: false` is parsed and then silently ignored.
    def self.apply_config(job : BaseJob, cfg : JobsConfig) : Nil
      case job
      {% for sc in BaseJob.subclasses %}
        {% class_name = sc.id.split("::").last.id.gsub(/Job$/, "").underscore %}
      when {{ sc.name }}
        job.cfg = cfg.{{ class_name }}
      {% end %}
      end
    end

    # The jobs `cfg` switches off, sorted so the startup warning reads the
    # same way on every boot: the generation order here follows the order the
    # job files happen to be required in, which is not a contract.
    def self.disabled_job_names(cfg : JobsConfig) : Array(String)
      names = [] of String

      {% for sc in BaseJob.subclasses %}
        {% class_name = sc.id.split("::").last.id.gsub(/Job$/, "").underscore %}
        names << {{ class_name.stringify }} if !cfg.{{ class_name }}.enable
      {% end %}

      names.sort!
    end
  end

  # A job is only started if BOTH gates let it through: the top-level key
  # that decides whether it is registered at all (`channel_threads`,
  # `popular_enabled`, ...) and its `jobs:` entry. `jobs:` can therefore
  # disable a job, but never re-enable one a top-level key turned off -
  # that job is never registered, so it never reaches this method.
  def self.register(job : BaseJob)
    apply_config(job, CONFIG.jobs)
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
