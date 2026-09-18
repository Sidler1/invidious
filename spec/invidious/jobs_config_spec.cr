require "../spec_helper"

# Same reason as config_validation_spec.cr: these specs need `Config` and the
# generated `JobsConfig`, neither of which spec_helper.cr pulls in on its own.
require "../../src/invidious/jobs/base_job"
# The job subclasses have to be loaded before `jobs`: the `jobs:` keys are
# generated from `BaseJob.subclasses`, so without them JobsConfig comes out
# empty and these specs would pass against nothing.
require "../../src/invidious/jobs/*"
require "../../src/invidious/jobs"
require "../../src/invidious/user/preferences"
require "../../src/invidious/config"

# The `jobs:` keys are generated from the class names (see the `macro finished`
# in jobs.cr), so nothing in the source spells them out. These specs are what
# pins the generated set: a job added, renamed or removed without updating
# config.example.yml fails here first.
Spectator.describe "Invidious::Jobs.disabled_job_names" do
  # Every job registered in src/invidious.cr, under the name the macro derives.
  ALL_JOB_NAMES = %w[
    clear_expired_items
    instance_list_refresh
    notification
    pull_popular_videos
    refresh_channels
    refresh_feeds
    statistics_refresh
    subscribe_to_feeds
  ]

  def jobs_config(yaml : String)
    Invidious::Jobs::JobsConfig.from_yaml(yaml)
  end

  it "generates a key for every registered job" do
    yaml = ALL_JOB_NAMES.join('\n') { |name| "#{name}:\n  enable: false" }
    expect(Invidious::Jobs.disabled_job_names(jobs_config(yaml))).to eq(ALL_JOB_NAMES)
  end

  it "reports nothing for a configuration that does not mention jobs" do
    expect(Invidious::Jobs.disabled_job_names(jobs_config("{}"))).to be_empty
  end

  it "reports nothing when every job is explicitly enabled" do
    yaml = ALL_JOB_NAMES.join('\n') { |name| "#{name}:\n  enable: true" }
    expect(Invidious::Jobs.disabled_job_names(jobs_config(yaml))).to be_empty
  end

  it "reports only the jobs that are disabled" do
    config = jobs_config("clear_expired_items:\n  enable: false\n")
    expect(Invidious::Jobs.disabled_job_names(config)).to eq(["clear_expired_items"])
  end

  it "reports several disabled jobs in a stable order" do
    config = jobs_config(<<-YAML)
      notification:
        enable: false
      clear_expired_items:
        enable: false
      YAML
    expect(Invidious::Jobs.disabled_job_names(config)).to eq(["clear_expired_items", "notification"])
  end
end

Spectator.describe "Invidious::Jobs.apply_config" do
  # ClearExpiredItemsJob takes no constructor arguments and its `begin` is
  # never called here, so this touches no database and starts no fiber.
  def a_job
    Invidious::Jobs::ClearExpiredItemsJob.new
  end

  it "disables a job the configuration turns off" do
    job = a_job
    Invidious::Jobs.apply_config(job, Invidious::Jobs::JobsConfig.from_yaml("clear_expired_items:\n  enable: false\n"))
    expect(job.cfg.enable).to be_false
  end

  # The upgrade guarantee: a config that says nothing about a job must leave
  # that job running exactly as it did before this wiring existed.
  it "leaves a job enabled when the configuration does not mention it" do
    job = a_job
    Invidious::Jobs.apply_config(job, Invidious::Jobs::JobsConfig.from_yaml("{}"))
    expect(job.cfg.enable).to be_true
  end

  it "leaves a job enabled when another job is the one disabled" do
    job = a_job
    Invidious::Jobs.apply_config(job, Invidious::Jobs::JobsConfig.from_yaml("notification:\n  enable: false\n"))
    expect(job.cfg.enable).to be_true
  end
end
