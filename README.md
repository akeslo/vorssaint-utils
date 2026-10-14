<p align="center">
  <img src="docs/assets/readme/moonlit.svg" width="220" alt="A small moon orbiting a ringed planet">
</p>

<h1 align="center">Moonlit Utils</h1>

<p align="center">
  A small moon in orbit around <a href="https://github.com/vorssaint/vorssaint-utils">Vorssaint</a>.<br>
  A few extras I wanted, built on someone else's excellent work.
</p>

> [!NOTE]
> This is an unofficial, personal fork and is not affiliated with or endorsed by Vorssaint. All the heavy lifting, and nearly all of the code, is the original project's, and it is wonderful. Please use and support [the real thing](https://github.com/vorssaint/vorssaint-utils).
>
> The extras here are features I built for myself and found useful, such as break reminders and the clipboard and PDF optimizers. Some of them are offered back upstream as pull requests. This is a passion project, not a product: **I don't plan to maintain it**, so expect no support, roadmap or release schedule. Take what helps, and if you want a polished, maintained app, go to upstream.

<!-- upstream-sync -->
Last synced with [vorssaint/vorssaint-utils](https://github.com/vorssaint/vorssaint-utils) at [`0b8e9440`](https://github.com/vorssaint/vorssaint-utils/commit/0b8e94404621849ef7da24523e5c16a9815a1bee) on 2026-10-14 ("docs(changelog): record reviewed island and input fixes"), after release v3.4.1.
<!-- /upstream-sync -->

## What this adds

Everything else in the app is the original project's. For the full feature list, install options and docs, see [upstream](https://github.com/vorssaint/vorssaint-utils#readme). These are the only things I added on top.

<!-- upstream-prs -->
Open pull requests I have offered upstream:

- [#2419](https://github.com/vorssaint/vorssaint-utils/pull/2419) feat: optimize copied images, videos and PDFs, and compress PDFs in Media tools
- [#2524](https://github.com/vorssaint/vorssaint-utils/pull/2524) feat(break-reminders): add eye and movement break reminders
<!-- /upstream-prs -->

<!-- adopted-prs -->
Other people's upstream pull requests I carry here until they merge:

- [#1879](https://github.com/vorssaint/vorssaint-utils/pull/1879) feat(port-manager): include UDP listeners, by [@bebricoOOOOOOf](https://github.com/bebricoOOOOOOf)
- [#2909](https://github.com/vorssaint/vorssaint-utils/pull/2909) fix(disk-image-installer): pops up when installing apps through homebrew, by [@LechTheMitch](https://github.com/LechTheMitch)
- [#2966](https://github.com/vorssaint/vorssaint-utils/pull/2966) fix(display): ignore DDC replies for another control, by [@morhaf-ko](https://github.com/morhaf-ko)
<!-- /adopted-prs -->

<!-- pr:2524 -->
### Break reminders

Eye and movement break reminders from the menu bar, with configurable sounds when a break starts and ends. When the activity list is empty, the break length is shown instead. Also offered upstream as [PR #2524](https://github.com/vorssaint/vorssaint-utils/pull/2524).
<!-- /pr:2524 -->

<!-- pr:2419 -->
### Clipboard optimizer

Shrinks what you copy before you paste it. Images, videos and PDFs each have their own on/off switch, plus conversion settings for HEIC-style images. Also offered upstream as [PR #2419](https://github.com/vorssaint/vorssaint-utils/pull/2419).
<!-- /pr:2419 -->

<!-- pr:2419 -->
### PDF compressor in Media tools

The same PDF engine as the clipboard optimizer, available as a tool in the Media workspace. It tells you when compression wouldn't make a file smaller. Part of the same PR.
<!-- /pr:2419 -->

### Rebase script

`scripts/sync-upstream.sh` rebases this branch onto upstream, runs the tests and pushes. It is how I keep this fork current.

## Build it yourself

```sh
git clone https://github.com/akeslo/vorssaint-utils.git
cd vorssaint-utils
./build.sh --install
```

Xcode Command Line Tools are the only requirement. There are no official builds of this fork.

## License

[GPL 3.0 or later](LICENSE), copyright 2026 Vorssaint. The license covers the source code; the Vorssaint name, logo and look are covered separately in [TRADEMARKS.md](TRADEMARKS.md), which is why this fork has its own name and logo. Rules for carried PRs and GPL duties: [docs/FORK-LICENSING.md](docs/FORK-LICENSING.md).
