class JbKaizen < Formula
  desc "Self-improving Claude Code setup with the Hoply day review"
  homepage "https://github.com/Moriarty33/jb-kaizen"
  url "https://github.com/Moriarty33/jb-kaizen/archive/refs/tags/v1.2.0.tar.gz"
  # Set at release: shasum -a 256 of the v1.2.0 tarball, then copy this file to the tap's Formula/.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on "jq"
  uses_from_macos "python"

  def install
    libexec.install Dir["*"], ".claude-plugin"
    (bin/"jb-kaizen").write <<~SH
      #!/bin/bash
      exec /bin/bash "#{libexec}/install-entry.sh" "$@"
    SH
  end

  def caveats
    <<~EOS
      Run `jb-kaizen` once: it adds the Claude Code plugin, the recommended set and,
      if you use Hoply, the day review (needs `claude` on PATH).
    EOS
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/jb-kaizen --version").strip
  end
end
