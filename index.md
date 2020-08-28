## GSoC 2020 Project Summary

Finish the package candidate workflow for Hackage and improved UI and candidate workflow for Hackage.
[GSoC branch](https://github.com/haskell/hackage-server/compare/sc/gsoc20)

### Things that done

- [Convert candidate page to use templating engine and delete candiates when published](https://github.com/haskell/hackage-server/pull/885):
  - Converted individual candidate page and candidate index page to template-based generation like servePackagePage does
  - Added two html templates, candidate-page.html.st and candidate-index.html.st, for these pages
  - Delete candidates automatically after they are published by setting doDelete to True
- [Added publish button on candidate page and show a link to the candidate packages available from the main package](https://github.com/haskell/hackage-server/commit/3f2c30ce5614406965994942f5c63d6305870ae4):
  - Added publish button on candidate page so users can publish the candidate directly
  - Added candidate section on the main package page with links
- [Added candidate link on user page](https://github.com/haskell/hackage-server/commit/3f2c30ce5614406965994942f5c63d6305870ae4):
  - By adding candidate link, user could go to the candidates page of that package.
  - The link would be wrong if the maintain group is a candidate
- [Added delete all candidates button on candidates page](https://github.com/haskell/hackage-server/commit/6c327990296dcdfc200b42bf88ed49908dfc1936):
  - Added delete all candidates button on candidates page, which redirect user to a candidates delete form
  - Created a candidates delete from to delete all candidates of a package
- [Expose Web UI for package candidates documentation](https://github.com/haskell/hackage-server/commit/483aaf6316c5fa8db4d8ea5d7d086aefb45f7fd0):
  - Created Web UI for candidates to upload documentation
- [Fixed links in Web UI for package candidates documentation](https://github.com/haskell/hackage-server/commit/da176f179745eb5c2fa7a49ebeb7db7b85d735ba):
  - Fixed the link on doc upload success page of candidates

### For Future

- Relative links in candidate view use wrong base
- Generate Package Candidates Index
