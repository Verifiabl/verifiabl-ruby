# frozen_string_literal: true

# Generated from https://docs.verifiabl.io/spec/p2-pii-text-profile-v1.json. Do not edit.
# Unicode source: https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt
# SHA-256: 2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c

module Verifiabl
  module Issuer
    module PiiTextProfile
      PROFILE_ID = "io.verifiabl.p2-pii-text.v1"
      UNICODE_VERSION = "17.0.0"
      PAYLOAD_MAX_BYTES = 1024
      FORMAT_CHARACTER_RANGES = [
        [0x00ad, 0x00ad],
        [0x0600, 0x0605],
        [0x061c, 0x061c],
        [0x06dd, 0x06dd],
        [0x070f, 0x070f],
        [0x0890, 0x0891],
        [0x08e2, 0x08e2],
        [0x180e, 0x180e],
        [0x200b, 0x200f],
        [0x202a, 0x202e],
        [0x2060, 0x2064],
        [0x2066, 0x206f],
        [0xfeff, 0xfeff],
        [0xfff9, 0xfffb],
        [0x110bd, 0x110bd],
        [0x110cd, 0x110cd],
        [0x13430, 0x1343f],
        [0x1bca0, 0x1bca3],
        [0x1d173, 0x1d17a],
        [0xe0001, 0xe0001],
        [0xe0020, 0xe007f]
      ].map(&:freeze).freeze
    end
  end
end
