cask "wechat-multi" do
  version "2.0.0"
  sha256 "01bf16aec77295ff09e44948b59682679f27f7352cfda4cebf87cd33f5b6359c"

  url "https://github.com/ashinno/wechat-multi/releases/download/v#{version}/WeChat-Multi-v#{version}.zip"
  name "WeChat Multi"
  desc "Menu bar app to run multiple WeChat accounts side by side"
  homepage "https://github.com/ashinno/wechat-multi"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :ventura"

  app "WeChat Multi.app"

  caveats <<~EOS
    WeChat Multi is ad-hoc signed, not notarized. The first time you launch it,
    right-click "WeChat Multi" in Finder and choose Open to get past Gatekeeper
    (you only need to do this once).

    It works by cloning /Applications/WeChat.app, so the official WeChat must be
    installed for it to do anything.
  EOS

  zap trash: [
    "~/Applications/WeChat Multi",
    "~/Library/Containers/com.wechatmulti.clone*",
    "~/Library/Preferences/com.wechatmulti.app.plist",
    "~/Library/Saved Application State/com.wechatmulti.app.savedState",
  ]
end
