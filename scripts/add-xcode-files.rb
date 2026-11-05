#!/usr/bin/env ruby
# Add existing files to targets in CommitStandings.xcodeproj without regenerating it
# (project.yml must never be used to regenerate the project; see AGENTS.md).
#
#   ruby scripts/add-xcode-files.rb CommitStandings,CommitStandingsiOS CommitStandings/Store/Foo.swift
#   ruby scripts/add-xcode-files.rb CommitStandingsiOS CommitStandingsiOS/BoardView.swift
#
# Swift files go into each target's Sources phase; anything else (asset catalogs, JSON
# fixtures) into its Resources phase. Groups mirror the folder path. Running it twice is a no-op.
# Needs the `xcodeproj` gem (`gem install xcodeproj`).
require "xcodeproj"

abort "usage: #{$0} <target>[,<target>...] <file>..." if ARGV.size < 2
root = File.expand_path("..", __dir__)
project = Xcodeproj::Project.open(File.join(root, "CommitStandings.xcodeproj"))
targets = ARGV[0].split(",").map do |name|
  project.targets.find { |t| t.name == name } or abort "no target named #{name}"
end

ARGV[1..].each do |path|
  absolute = File.expand_path(path, root)
  abort "#{path} does not exist" unless File.exist?(absolute)
  relative = absolute.delete_prefix("#{root}/")
  ref = project.files.find { |f| f.real_path.to_s == absolute }
  unless ref
    group = File.dirname(relative).split("/").reduce(project.main_group) do |g, name|
      g.children.find { |c| c.isa == "PBXGroup" && c.display_name == name } || g.new_group(name, name)
    end
    ref = group.new_reference(File.basename(relative))
  end
  targets.each do |target|
    phase = path.end_with?(".swift") ? target.source_build_phase : target.resources_build_phase
    next if phase.files_references.include?(ref)
    phase.add_file_reference(ref, true)
    puts "#{relative} -> #{target.name}"
  end
end
project.save
