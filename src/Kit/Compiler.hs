module Kit.Compiler (
  tryCompile,
  module Kit.Compiler.Context,
  module Kit.Compiler.Module
) where

  import Control.Exception
  import Control.Monad
  import Data.List
  import System.Directory
  import System.FilePath
  import Kit.Ast
  import Kit.Compiler.Context
  import Kit.Compiler.Module
  import Kit.Error
  import Kit.Hash
  import Kit.Parser
  import Kit.Str

  tryCompile :: CompileContext -> IO (Either Errors ())
  tryCompile context = try $ compile context

  {-
    Run compilation to completion from the given CompileContext. Throws an
    Error on failure.
  -}
  compile :: CompileContext -> IO ()
  compile ctx = do
    modules <- h_new
    let ctx' = ctx {context_modules = modules}
    mainModule <- loadModule ctx' (context_main_module ctx') Nothing
    return ()

  loadModule :: CompileContext -> ModulePath -> Maybe Span -> IO Module
  loadModule ctx mod pos = do
    existing <- h_lookup (context_modules ctx) mod
    case existing of
      Just x -> return x
      Nothing -> do
        exprs <- parseModuleExprs ctx mod pos
        let m = new_mod mod exprs
        errs <- foldM (_loadImportedModule ctx) [] (mod_imports m)
        if errs == []
          then return m
          else throw $ Errs errs

  _loadImportedModule :: CompileContext -> [Error] -> (ModulePath, Span) -> IO [Error]
  _loadImportedModule ctx acc (mod, pos) = do
    result <- try $ loadModule ctx mod (Just pos)
    return $ case result of
      Left (Errs errs) -> acc ++ errs
      Right m -> acc

  parseModuleExprs :: CompileContext -> ModulePath -> Maybe Span -> IO [Expr]
  parseModuleExprs ctx mod pos = do
    path <- (findModule ctx mod pos)
    parsed <- parseFile path
    case parsed of
      ParseResult r -> return r
      Err e -> throw $ Errs [e]

  findModule :: CompileContext -> ModulePath -> Maybe Span -> IO FilePath
  findModule ctx mod pos = do
    let modPath = replaceExtension (joinPath (map s_unpack mod)) ".kit"
    let searchPaths = [dir </> modPath | dir <- context_source_paths ctx]
    matches <- filterM doesFileExist searchPaths
    if matches == []
      then throw $ Errs $ [
        errp ImportError ("Couldn't find module " ++ s_unpack (showModulePath mod) ++
                          "; tried searching the following locations: \n\n" ++
                          (intercalate "\n" (map (\f -> "  - " ++ f) searchPaths)))
             pos
        ]
      else return $ head matches
