# frozen_string_literal: true

require_relative "lib/rehash/web"
require_relative "lib/rehash/scheduler"

Rehash::Scheduler.start

run Rehash::Web
