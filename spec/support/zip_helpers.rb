# frozen_string_literal: true

require "securerandom"

module ZipHelpers
  def build_zip(entries = {}, password: nil, name: "archive.zip", **files)
    entries = entries.merge(files)
    path = File.join(Dir.mktmpdir("zip_guard_spec"), name)
    encrypter = password && Zip::TraditionalEncrypter.new(password)
    Zip::OutputStream.open(path, encrypter: encrypter) do |zip|
      entries.each do |entry_name, content|
        zip.put_next_entry(entry_name)
        zip.write(content)
      end
    end
    path
  end

  def build_partially_encrypted_zip(plain:, encrypted:, password: "secret")
    path = File.join(Dir.mktmpdir("zip_guard_spec"), "partial.zip")
    Zip::OutputStream.open(path) do |zip|
      plain.each { |name, content| write_entry(zip, name, content, Zip::NullEncrypter.new) }
      encrypted.each { |name, content| write_entry(zip, name, content, Zip::TraditionalEncrypter.new(password)) }
    end
    path
  end

  def write_entry(zip, name, content, encrypter)
    zip.send(:finalize_current_entry)
    zip.instance_variable_set(:@encrypter, encrypter)
    zip.put_next_entry(name)
    zip.write(content)
  end

  def understate_sizes(path, size)
    data = File.binread(path).b
    patch_headers(data, "PK\x03\x04".b, 22, size)
    patch_headers(data, "PK\x01\x02".b, 24, size)
    File.binwrite(path, data)
    path
  end

  def patch_headers(data, signature, offset, size)
    index = 0
    while (index = data.index(signature, index))
      data[index + offset, 4] = [size].pack("V")
      index += 4
    end
  end

  def zip_content(entries = {}, password: nil, **files)
    File.binread(build_zip(entries, password: password, **files))
  end

  def nested_zip(levels, innermost)
    levels.times.reduce(innermost) { |content, level| zip_content("level#{level}.zip" => content) }
  end

  def write_file(content, name: "file.bin")
    path = File.join(Dir.mktmpdir("zip_guard_spec"), name)
    File.binwrite(path, content)
    path
  end
end
