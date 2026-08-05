require 'xcodeproj'
project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)
main_group = project.main_group.find_subpath(File.join('Runner'), true)

# Add the file reference
file_path = 'enything_bell.wav'
file_ref = main_group.find_file_by_path(file_path) || main_group.new_file(file_path)

# Add the file to the app target's resources build phase
target = project.targets.find { |t| t.name == 'Runner' }
resources_build_phase = target.resources_build_phase

unless resources_build_phase.files_references.include?(file_ref)
  resources_build_phase.add_file_reference(file_ref, true)
  puts "Added enything_bell.wav to Xcode Resources Build Phase."
else
  puts "enything_bell.wav is already in the Xcode Resources Build Phase."
end

project.save
