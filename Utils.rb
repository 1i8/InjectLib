# frozen_string_literal: true

# Check if a file exists.
# Parameters:
#   file_path: File path
# Returns:
#   Boolean indicating whether the file exists.
def file_exist?(file_path)
  File.exist?(file_path)
end