-- Body of the HTML page for a package
{-# LANGUAGE PatternGuards, RecordWildCards #-}
module Distribution.Server.Pages.Package (
    packagePage,
    renderDependencies,
    renderVersion,
    renderFields,
    renderDownloads,
    renderChangelog
  ) where

import Distribution.Server.Features.PreferredVersions

import Distribution.Server.Pages.Template (hackagePageWith)
import Distribution.Server.Pages.Package.HaddockParse (parseHaddockParagraphs)
import Distribution.Server.Pages.Package.HaddockLex  (tokenise)
import Distribution.Server.Pages.Package.HaddockHtml
import Distribution.Server.Packages.ModuleForest
import Distribution.Server.Packages.Render
import Distribution.Server.Users.Types (userStatus, userName, isActiveAccount)
import Data.TarIndex (TarIndex)

import Distribution.Package
import Distribution.PackageDescription as P
import Distribution.Simple.Utils ( cabalVersion )
import Distribution.Version
import Distribution.Text        (display)
import Text.XHtml.Strict hiding (p, name, title, content)

import Data.Monoid              (Monoid(..))
import Data.Maybe               (maybeToList, isJust)
import Data.List                (intersperse, intercalate)
import System.FilePath.Posix    ((</>), (<.>), takeFileName)
import Data.Time.Locale.Compat  (defaultTimeLocale)
import Data.Time.Format         (formatTime)

import Cheapskate (markdown, Options(..))
import Cheapskate.Html (renderDoc)

import qualified Text.Blaze.Html.Renderer.Pretty as Blaze (renderHtml)
import qualified Data.Text.Encoding as T (decodeUtf8)
import qualified Data.ByteString.Lazy as BS (ByteString, toStrict)

packagePage :: PackageRender -> [Html] -> [Html] -> [(String, Html)]
            -> [(String, Html)] -> Maybe TarIndex -> URL -> Bool
            -> Html
packagePage render headLinks top sections bottom mdocIndex docURL isCandidate =
    hackagePageWith [canonical] docTitle docSubtitle docBody [docFooter]
  where
    pkgid   = rendPkgId render
    pkgName = display $ packageName pkgid

    canonical = thelink ! [ rel "canonical"
                          , href ("/package/" ++ pkgName) ] << noHtml
    docTitle = pkgName
            ++ case synopsis (rendOther render) of
                 ""    -> ""
                 short -> ": " ++ short
    docSubtitle = toHtml docTitle

    docBody = h1 << bodyTitle
          : concat [
             renderHeads,
             top,
             pkgBody render sections,
             moduleSection render mdocIndex docURL,
             packageFlags render,
             downloadSection render,
             maintainerSection pkgid isCandidate,
             map pair bottom
           ]
    bodyTitle = "The " ++ pkgName ++ " package"

    renderHeads = case headLinks of
        [] -> []
        items -> [thediv ! [thestyle "font-size: small"] <<
            (map (\item -> "[" +++ item +++ "] ") items)]

    docFooter = thediv ! [identifier "footer"]
                  << paragraph
                       << [ toHtml "Produced by "
                          , anchor ! [href "/"] << "hackage"
                          , toHtml " and "
                          , anchor ! [href cabalHomeURL] << "Cabal"
                          , toHtml (" " ++ display cabalVersion) ]

    pair (title, content) =
        toHtml [ h2 << title, content ]

-- | Body of the package page
pkgBody :: PackageRender -> [(String, Html)] -> [Html]
pkgBody render sections =
    descriptionSection render
 ++ propertySection sections

descriptionSection :: PackageRender -> [Html]
descriptionSection p@PackageRender{..} =
        prologue p
     ++ readmeLink
  where
    readmeLink = case rendReadme of
      Just _ -> [ hr
                , ulist << li << anchor ! [href readmeURL] << "ReadMe"
                ]
      _      -> []
    readmeURL  = rendPkgUri </> "readme"

prologue :: PackageRender -> [Html]
prologue PackageRender{..} =
  renderHaddock (description rendOther)
{-
  --TODO: need to improve the display of the description / readme
  -- just having both is too much in many cases. Perhaps we should
  -- use the readme only if the description is empty. And otherwise just link.
  -- Also, we need to limit the length of both the description and readme
  -- or it pushes everything else off the page
  (case rendReadme of
    Nothing -> []
    Just (_, readme) -> [renderMarkdown readme])
-}

renderHaddock :: String -> [Html]
renderHaddock []   = []
renderHaddock desc =
  case tokenise desc >>= parseHaddockParagraphs of
      Nothing  -> [paragraph << p | p <- paragraphs desc]
      Just doc -> [markup htmlMarkup doc]

renderMarkdown :: BS.ByteString -> Html
renderMarkdown = primHtml . Blaze.renderHtml . renderDoc . markdown opts
               . T.decodeUtf8 . BS.toStrict
  where
    opts =
      Options
        { sanitize = True
        , allowRawHtml = False
        , preserveHardBreaks = False
        , debug = False
        }


-- Break text into paragraphs (separated by blank lines)
paragraphs :: String -> [String]
paragraphs = map unlines . paras . lines
  where paras xs = case dropWhile null xs of
                [] -> []
                xs' -> case break null xs' of
                        (para, xs'') -> para : paras xs''

downloadSection :: PackageRender -> [Html]
downloadSection PackageRender{..} =
    [ h2 << "Downloads"
    , ulist << map (li <<) downloadItems
    ]
  where
    downloadItems =
      [ if rendHasTarball
          then [ anchor ! [href downloadURL] << tarGzFileName
               , toHtml << " ["
               , anchor ! [href srcURL] << "browse"
               , toHtml << "]"
               , toHtml << " (Cabal source package)"
               ]
          else [ toHtml << "Package tarball not uploaded" ]
      , [ anchor ! [href cabalURL] << "Package description"
        , toHtml $ if rendHasTarball then " (included in the package)" else ""
        ]
      ]

    downloadURL   = rendPkgUri </> display rendPkgId <.> "tar.gz"
    cabalURL      = rendPkgUri </> display (packageName rendPkgId) <.> "cabal"
    srcURL        = rendPkgUri </> "src/"
    tarGzFileName = display rendPkgId ++ ".tar.gz"

maintainerSection :: PackageId -> Bool -> [Html]
maintainerSection pkgid isCandidate =
    [ h4 << "Maintainers' corner"
    , paragraph << "For package maintainers and hackage trustees"
    , ulist << li << anchor ! [href maintainURL]
                  << "edit package information"
    ]
  where
    maintainURL | isCandidate = "candidate/maintain"
                | otherwise   = display (packageName pkgid) </> "maintain"

-- | Render a table of the package's flags and along side it a tip
-- indicating how to enable/disable flags with Cabal.
packageFlags :: PackageRender -> [Html]
packageFlags render =
  case rendFlags render of
    [] -> mempty
    flags ->
      [h2 << "Flags"
      ,flagsTable flags
      ,tip]
  where tip =
          paragraph ! [theclass "tip"] <<
          [thespan << "Use "
          ,code "-f <flag>"
          ,thespan << " to enable a flag, or "
          ,code "-f -<flag>"
          ,thespan << " to disable that flag. "
          ,anchor ! [href tipLink] << "More info"
          ]
        tipLink = "http://www.haskell.org/cabal/users-guide/installing-packages.html#controlling-flag-assignments"
        flagsTable flags =
          table ! [theclass "flags-table"] <<
          [thead << flagsHeadings
          ,tbody << map flagRow flags]
        flagsHeadings = [th << "Name"
                        ,th << "Description"
                        ,th << "Default"]
        flagRow flag =
          tr << [td ! [theclass "flag-name"]   << code (case flagName flag of FlagName name -> name)
                ,td ! [theclass "flag-desc"]   << flagDescription flag
                ,td ! [theclass (if flagDefault flag then "flag-enabled" else "flag-disabled")] <<
                 if flagDefault flag then "Enabled" else "Disabled"]
        code = (thespan ! [theclass "code"] <<)

moduleSection :: PackageRender -> Maybe TarIndex -> URL -> [Html]
moduleSection render mdocIndex docURL =
    maybeToList $ fmap msect (rendModules render mdocIndex)
  where msect libModuleForrest = toHtml
            [ h2 << "Modules"
            , renderModuleForest docURL libModuleForrest
            , renderDocIndexLink
            ]
        renderDocIndexLink
          | isJust mdocIndex =
            let docIndexURL = docURL </> "doc-index.html"
            in  paragraph ! [thestyle "font-size: small"]
                  << ("[" +++ anchor ! [href docIndexURL] << "Index" +++ "]")
          | otherwise = mempty

propertySection :: [(String, Html)] -> [Html]
propertySection sections =
    [ h2 << "Properties"
    , tabulate $ filter (not . isNoHtml . snd) sections
    ]

tabulate :: [(String, Html)] -> Html
tabulate items = table ! [theclass "properties"] <<
        [tr << [th << t, td << d] | (t, d) <- items]


renderDependencies :: PackageRender -> (String, Html)
renderDependencies render =
    ("Dependencies", case rendDepends render of
                       []   -> toHtml "None"
                       deps -> showDependencies deps)

showDependencies :: [Dependency] -> Html
showDependencies deps = commaList (map showDependency deps)

showDependency ::  Dependency -> Html
showDependency (Dependency (PackageName pname) vs) = showPkg +++ vsHtml
  where vsHtml = if vs == anyVersion then noHtml
                                     else toHtml (" (" ++ display vs ++ ")")
        -- mb_vers links to latest version in range. This is a bit computationally
        -- expensive, not cache-friendly, and perhaps unexpected in some cases
        {-mb_vers = maybeLast $ filter (`withinRange` vs) $ map packageVersion $
                    PackageIndex.lookupPackageName vmap (PackageName pname)-}
        -- nonetheless, we should ensure that the package exists /before/
        -- passing along the PackageRender, which is not the case here
        showPkg = anchor ! [href . packageURL $ PackageIdentifier (PackageName pname) (Version [] [])] << pname

renderVersion :: PackageId -> [(Version, VersionStatus)] -> Maybe String -> (String, Html)
renderVersion (PackageIdentifier pname pversion) allVersions info =
    (if null earlierVersions && null laterVersions then "Version" else "Versions", versionList +++ infoHtml)
  where (earlierVersions, laterVersionsInc) = span ((<pversion) . fst) allVersions
        (mThisVersion, laterVersions) = case laterVersionsInc of
            (v:later) | fst v == pversion -> (Just v, later)
            later -> (Nothing, later)
        versionList = commaList $ map versionedLink earlierVersions
                               ++ (case pversion of
                                      Version [] [] -> []
                                      _ -> [strong ! (maybe [] (status . snd) mThisVersion) << display pversion]
                                  )
                               ++ map versionedLink laterVersions
        versionedLink (v, s) = anchor ! (status s ++ [href $ packageURL $ PackageIdentifier pname v]) << display v
        status st = case st of
            NormalVersion -> []
            DeprecatedVersion  -> [theclass "deprecated"]
            UnpreferredVersion -> [theclass "unpreferred"]
        infoHtml = case info of Nothing -> noHtml; Just str -> " (" +++ (anchor ! [href str] << "info") +++ ")"

renderChangelog :: PackageRender -> (String, Html)
renderChangelog render =
    ("Change log", case rendChangeLog render of
                     Nothing            -> toHtml "None available"
                     Just (_,_,_,fname) -> anchor ! [href changeLogURL]
                                                 << takeFileName fname)
  where
    changeLogURL  = rendPkgUri render </> "changelog"

-- We don't keep currently per-version downloads in memory; if we decide that
-- it is important to show this all the time, we can reenable
renderDownloads :: Int -> Int -> {- Int -> Version -> -} (String, Html)
renderDownloads totalDown recentDown {- versionDown version -} =
    ("Downloads", toHtml $ {- show versionDown ++ " for " ++ display version ++
                      " and " ++ -} show totalDown ++ " total (" ++
                      show recentDown ++ " in last 30 days)")

renderFields :: PackageRender -> [(String, Html)]
renderFields render = [
        -- Cabal-Version
        ("License",     rendLicense),
        ("Copyright",   toHtml $ P.copyright desc),
        ("Author",      toHtml $ author desc),
        ("Maintainer",  maintainField $ rendMaintainer render),
        ("Stability",   toHtml $ stability desc),
        ("Category",    commaList . map categoryField $ rendCategory render),
        ("Home page",   linkField $ homepage desc),
        ("Bug tracker", linkField $ bugReports desc),
        ("Source repository", vList $ map sourceRepositoryField $ sourceRepos desc),
        ("Executables", commaList . map toHtml $ rendExecNames render),
        ("Uploaded", uncurry renderUploadInfo (rendUploadInfo render))
      ]
   ++ [ ("Updated", renderUpdateInfo revisionNo utime uinfo)
      | (revisionNo, utime, uinfo) <- maybeToList (rendUpdateInfo render) ]
  where
    desc = rendOther render
    renderUploadInfo utime uinfo =
        formatTime defaultTimeLocale "%c" utime +++ " by " +++ user
      where
        uname   = maybe "Unknown" (display . userName) uinfo
        uactive = maybe False (isActiveAccount . userStatus) uinfo
        user | uactive   = anchor ! [href $ "/user/" ++ uname] << uname
             | otherwise = toHtml uname

    renderUpdateInfo revisionNo utime uinfo =
        renderUploadInfo utime uinfo +++ " to " +++
        anchor ! [href revisionsURL] << ("revision " +++ show revisionNo)
      where
        revisionsURL = display (rendPkgId render) </> "revisions/"

    linkField url = case url of
        [] -> noHtml
        _  -> anchor ! [href url] << url
    categoryField cat = anchor ! [href $ "/packages/#cat:" ++ cat] << cat
    maintainField mnt = case mnt of
        Nothing -> strong ! [theclass "warning"] << toHtml "none"
        Just n  -> toHtml n
    sourceRepositoryField sr = sourceRepositoryToHtml sr
    
    rendLicense = case rendLicenseFiles render of
      []            -> toHtml (rendLicenseName render)
      [licenseFile] -> anchor ! [ href (rendPkgUri render </> "src" </> licenseFile) ]
                             << rendLicenseName render
      _licenseFiles -> toHtml (rendLicenseName render)
                       +++ "["
                       +++ anchor ! [ href (rendPkgUri render </> "src") ]
                                 << "multiple licese files"
                       +++ "]"


sourceRepositoryToHtml :: SourceRepo -> Html
sourceRepositoryToHtml sr
    = toHtml (display (repoKind sr) ++ ": ")
  +++ case repoType sr of
      Just Darcs
       | (Just url, Nothing, Nothing) <-
         (repoLocation sr, repoModule sr, repoBranch sr) ->
          concatHtml [toHtml "darcs get ",
                      anchor ! [href url] << toHtml url,
                      case repoTag sr of
                          Just tag' -> toHtml (" --tag " ++ tag')
                          Nothing   -> noHtml,
                      case repoSubdir sr of
                          Just sd -> toHtml " ("
                                 +++ (anchor ! [href (url </> sd)]
                                      << toHtml sd)
                                 +++ toHtml ")"
                          Nothing   -> noHtml]
      Just Git
       | (Just url, Nothing) <-
         (repoLocation sr, repoModule sr) ->
          concatHtml [toHtml "git clone ",
                      anchor ! [href url] << toHtml url,
                      case repoBranch sr of
                          Just branch -> toHtml (" -b " ++ branch)
                          Nothing     -> noHtml,
                      case repoTag sr of
                          Just tag' -> toHtml ("(tag " ++ tag' ++ ")")
                          Nothing   -> noHtml,
                      case repoSubdir sr of
                          Just sd -> toHtml ("(" ++ sd ++ ")")
                          Nothing -> noHtml]
      Just SVN
       | (Just url, Nothing, Nothing, Nothing) <-
         (repoLocation sr, repoModule sr, repoBranch sr, repoTag sr) ->
          concatHtml [toHtml "svn checkout ",
                      anchor ! [href url] << toHtml url,
                      case repoSubdir sr of
                          Just sd -> toHtml ("(" ++ sd ++ ")")
                          Nothing   -> noHtml]
      Just CVS
       | (Just url, Just m, Nothing, Nothing) <-
         (repoLocation sr, repoModule sr, repoBranch sr, repoTag sr) ->
          concatHtml [toHtml "cvs -d ",
                      anchor ! [href url] << toHtml url,
                      toHtml (" " ++ m),
                      case repoSubdir sr of
                          Just sd -> toHtml ("(" ++ sd ++ ")")
                          Nothing   -> noHtml]
      Just Mercurial
       | (Just url, Nothing) <-
         (repoLocation sr, repoModule sr) ->
          concatHtml [toHtml "hg clone ",
                      anchor ! [href url] << toHtml url,
                      case repoBranch sr of
                          Just branch -> toHtml (" -b " ++ branch)
                          Nothing     -> noHtml,
                      case repoTag sr of
                          Just tag' -> toHtml (" -u " ++ tag')
                          Nothing   -> noHtml,
                      case repoSubdir sr of
                          Just sd -> toHtml ("(" ++ sd ++ ")")
                          Nothing   -> noHtml]
      Just Bazaar
       | (Just url, Nothing, Nothing) <-
         (repoLocation sr, repoModule sr, repoBranch sr) ->
          concatHtml [toHtml "bzr branch ",
                      anchor ! [href url] << toHtml url,
                      case repoTag sr of
                          Just tag' -> toHtml (" -r " ++ tag')
                          Nothing -> noHtml,
                      case repoSubdir sr of
                          Just sd -> toHtml ("(" ++ sd ++ ")")
                          Nothing   -> noHtml]
      _ ->
          -- We don't know how to show this SourceRepo.
          -- This is a kludge so that we at least show all the info.
          toHtml (show sr)

commaList :: [Html] -> Html
commaList = concatHtml . intersperse (toHtml ", ")

vList :: [Html] -> Html
vList = concatHtml . intersperse br
-----------------------------------------------------------------------------

renderModuleForest :: URL -> ModuleForest -> Html
renderModuleForest docUrl forest =
    thediv ! [identifier "module-list"] << renderForest [] forest
    where
      renderForest _       [] = noHtml
      renderForest pathRev ts = myUnordList $ map renderTree ts
          where
            renderTree (Node s isModule hasDocs subs) =
                    ( if isModule then moduleEntry hasDocs newPath
                                  else italics << s )
                +++ renderForest newPathRev subs
                where
                  newPathRev = s:pathRev
                  newPath = reverse newPathRev

      moduleEntry False path =
          thespan ! [theclass "module"] << modName path
      moduleEntry True path =
          thespan ! [theclass "module"] << linkedName path
      modName path = toHtml (intercalate "." path)
      linkedName path = anchor ! [href modUrl] << modName path
          where
            modUrl = docUrl ++ "/" ++ intercalate "-" path ++ ".html"
      myUnordList :: HTML a => [a] -> Html
      myUnordList = unordList ! [theclass "modules"]

------------------------------------------------------------------------------
-- TODO: most of these should be available from the CoreFeature
-- so pass it in to this module

-- | URL describing a package.
packageURL :: PackageIdentifier -> URL
packageURL pkgId = "/package" </> display pkgId

--cabalLogoURL :: URL
--cabalLogoURL = "/built-with-cabal.png"

-- global URLs
cabalHomeURL :: URL
cabalHomeURL = "http://haskell.org/cabal/"
