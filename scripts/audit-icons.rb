#!/usr/bin/env ruby
# frozen_string_literal: true

require "set"

ROOT = File.expand_path("..", __dir__)
APP_ICON_PATH = File.join(ROOT, "ClaudeStats", "Utilities", "AppIcon.swift")
SWIFT_ROOT = File.join(ROOT, "ClaudeStats")

ALLOWED_DUPLICATES = {
  "arrow.down.circle" => %w[Action.download NotchIsland.downloads],
  "battery.75percent" => %w[NotchIsland.battery SystemMonitor.battery],
  "capsule.portrait.tophalf.filled" => %w[NotchIsland.island Settings.notchIsland],
  "checkmark.shield" => %w[Network.certificates Status.secure],
  "curlybraces" => %w[Code.braces Session.typeName],
  "doc" => %w[AIConfig.document Resource.document],
  "doc.text" => %w[AIConfig.instruction Resource.documentText],
  "exclamationmark.triangle" => %w[AIConfig.diagnostics Status.warning],
  "externaldrive.badge.checkmark" => %w[Resource.externalDriveReady Skill.installed],
  "gauge.with.dots.needle.33percent" => %w[Metric.gauge NotchIsland.stats],
  "info.circle" => %w[Settings.about Status.info],
  "list.bullet.clipboard" => %w[Network.rules Resource.clipboardList],
  "magnifyingglass" => %w[Action.search Skill.discover],
  "person" => %w[People.person Session.roleUser],
  "puzzlepiece.extension" => %w[AIConfig.pluginManifest NotchIsland.extensionBridge Resource.plugin Skill.file],
  "terminal.fill" => %w[Runtime.terminal Runtime.terminalFilled Workspace.terminal],
  "tray.and.arrow.down" => %w[Action.downloadTray NotchIsland.shelf],
  "viewfinder" => %w[Action.viewfinder NotchIsland.screenAssistant],
  "wand.and.stars" => %w[Feature.magic Session.roleAssistant],
  "xmark.octagon.fill" => %w[Status.failureCircle Status.failureFilled],
}.transform_values { |names| names.to_set }.freeze

def parse_app_icon
  namespace = nil
  defs = {}
  lines = {}

  File.readlines(APP_ICON_PATH).each_with_index do |line, index|
    namespace = $1 if line =~ /^\s*enum\s+(\w+)\s*\{/
    next unless namespace && line =~ /^\s*static let\s+(\w+)\s*=\s*(.+)$/

    name = "#{namespace}.#{$1}"
    expr = $2.strip.sub(/\s*\/\/.*$/, "")
    defs[name] = expr
    lines[name] = index + 1
  end

  [defs, lines]
end

def resolve_icon(defs, name, seen = [])
  return nil if seen.include?(name)

  expr = defs[name]
  return nil unless expr

  case expr
  when /^"([^"]+)"$/
    Regexp.last_match(1)
  when /^(?:AppIcon\.)?(\w+)\.(\w+)$/
    resolve_icon(defs, "#{Regexp.last_match(1)}.#{Regexp.last_match(2)}", seen + [name])
  when /^(\w+)$/
    namespace = name.split(".").first
    resolve_icon(defs, "#{namespace}.#{Regexp.last_match(1)}", seen + [name])
  end
end

defs, lines = parse_app_icon
groups = Hash.new { |hash, key| hash[key] = [] }

defs.keys.sort.each do |name|
  resolved = resolve_icon(defs, name)
  groups[resolved] << name if resolved
end

duplicates = groups.select { |_symbol, names| names.size > 1 }.sort_by { |symbol, names| [-names.size, symbol] }
unexpected_duplicates = []

puts "AppIcon duplicate resolved symbols:"
if duplicates.empty?
  puts "  none"
else
  duplicates.each do |symbol, names|
    allowed = ALLOWED_DUPLICATES[symbol]
    status = allowed && names.to_set.subset?(allowed) ? "allowed" : "unexpected"
    puts "  #{status}: #{symbol}"
    names.each { |name| puts "    #{name}:#{lines[name]}" }
    unexpected_duplicates << [symbol, names] if status == "unexpected"
  end
end

raw_icon_pattern = /Image\s*\(\s*systemName:\s*"|systemImage:\s*"|symbol:\s*"/
raw_icon_hits = []

Dir.glob(File.join(SWIFT_ROOT, "**", "*.swift")).sort.each do |path|
  next if path == APP_ICON_PATH

  File.readlines(path).each_with_index do |line, index|
    next unless line.match?(raw_icon_pattern)
    next if path.end_with?("ClaudeStats/Services/Skills/SkillsLocalScanner.swift") && line.include?("SkillProviderDefinition")

    raw_icon_hits << "#{path.delete_prefix("#{ROOT}/")}:#{index + 1}:#{line.strip}"
  end
end

puts
puts "Raw app-owned icon callsites:"
if raw_icon_hits.empty?
  puts "  none"
else
  raw_icon_hits.each { |hit| puts "  #{hit}" }
end

exit(unexpected_duplicates.empty? && raw_icon_hits.empty? ? 0 : 1)
