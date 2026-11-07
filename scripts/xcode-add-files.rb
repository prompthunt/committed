#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds existing files to targets in CommitStandings.xcodeproj without regenerating the
# project from project.yml (which would reset the Mac app's Info.plist, entitlements, and
# Sparkle setup). Idempotent: running it twice changes nothing.
#
#   ruby scripts/xcode-add-files.rb --targets CommitStandings,CommitStandingsiOS \
#     CommitStandings/Store/NewSharedThing.swift
#
# Swift files go in each target's Sources phase; anything else goes in Resources.
# Files under CommitStandings/ and CommitStandingsTests/ live in ordinary groups and need this
# script. Files under the iOS folders (CommitStandingsiOS/, CommitStandingsLiveRank/,
# CommitStandingsiOSTests/) are filesystem-synchronized: their own target picks them up
# automatically, and this script refuses to touch them.
#
# Requires the xcodeproj gem (`gem install xcodeproj`).

require 'optparse'
require 'pathname'
require 'xcodeproj'

ROOT = Pathname.new(File.expand_path('..', __dir__))
PROJECT_PATH = ROOT.join('CommitStandings.xcodeproj')

target_names = []
OptionParser.new do |opts|
  opts.banner = 'Usage: ruby scripts/xcode-add-files.rb --targets A,B FILE...'
  opts.on('--targets LIST', 'Comma-separated target names') { |v| target_names = v.split(',').map(&:strip) }
end.parse!

abort 'Pass --targets and at least one file.' if target_names.empty? || ARGV.empty?

project = Xcodeproj::Project.open(PROJECT_PATH)
targets = target_names.map do |name|
  project.targets.find { |t| t.name == name } ||
    abort("No target named #{name}. Targets: #{project.targets.map(&:name).join(', ')}")
end

synced_folders = project.objects.grep(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup).map(&:path)

# Finds or creates the group chain for a directory relative to the project root, matching the
# existing layout where each group's path is its folder name.
def group_for(project, dir)
  group = project.main_group
  Pathname.new(dir).each_filename do |component|
    child = group.children.find do |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && (c.path == component || (c.path.nil? && c.name == component))
    end
    group = child || group.new_group(component, component)
  end
  group
end

ARGV.each do |raw|
  absolute = Pathname.new(File.expand_path(raw, Dir.pwd))
  abort "#{raw} does not exist." unless absolute.exist?
  relative = absolute.relative_path_from(ROOT).to_s
  if (folder = synced_folders.find { |f| relative.start_with?("#{f}/") })
    abort "#{relative} is in the synchronized folder #{folder}/; its target includes it automatically. " \
          'Move it to CommitStandings/ if more than one target needs it.'
  end

  ref = project.files.find { |f| f.real_path == absolute }
  ref ||= group_for(project, File.dirname(relative)).new_reference(absolute.to_s)

  targets.each do |target|
    phase = relative.end_with?('.swift') ? target.source_build_phase : target.resources_build_phase
    if phase.files_references.include?(ref)
      puts "= #{relative} already in #{target.name}"
    else
      phase.add_file_reference(ref, true)
      puts "+ #{relative} -> #{target.name}"
    end
  end
end

project.save
