cask "floating-lyrics" do
  version "0.3"
  sha256 "cca73b6caa128485025cc5a59ba163d399168a238aad767868ee29f84af1e602"

  url "https://github.com/minhchienwikipedia/floating-lyrics/releases/download/v#{version}/FloatingLyrics-#{version}.dmg"
  name "Floating Lyrics"
  desc "Synced desktop lyrics for Apple Music, Spotify and YouTube Music"
  homepage "https://github.com/minhchienwikipedia/floating-lyrics"

  depends_on macos: :sequoia

  app "FloatingLyrics.app"

  # The app is ad-hoc signed, not notarized, so clear the download quarantine
  # to let it open without the "Apple could not verify…" prompt.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/FloatingLyrics.app"]
  end

  uninstall quit: "local.floatinglyrics"

  zap trash: [
    "~/Library/Preferences/local.floatinglyrics.helper.plist",
    "~/Library/Preferences/local.floatinglyrics.plist",
  ]
end
