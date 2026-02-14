cask "dict" do
  version "0.1.0"
  sha256 "" # TODO: fill after first release

  # TODO: update URL to actual GitHub repo
  url "https://github.com/OWNER/dict/releases/download/v#{version}/Dict.dmg"
  name "Dict"
  desc "Voice-to-text menu bar app with global hotkey"
  homepage "https://github.com/OWNER/dict"

  depends_on macos: ">= :sonoma"

  app "Dict.app"

  zap trash: [
    "~/.config/dict",
  ]
end
