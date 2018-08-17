module Kit.Compiler.Typers.AutoRefDeref where

import Control.Applicative
import Control.Monad
import Data.IORef
import Data.List
import Kit.Ast
import Kit.Compiler.Binding
import Kit.Compiler.Context
import Kit.Compiler.Module
import Kit.Compiler.Scope
import Kit.Compiler.TermRewrite
import Kit.Compiler.TypeContext
import Kit.Compiler.TypedExpr
import Kit.Compiler.Typers.Base
import Kit.Compiler.Typers.ConvertExpr
import Kit.Compiler.Unify
import Kit.Error
import Kit.HashTable
import Kit.Parser
import Kit.Str

autoRefDeref
  :: CompileContext
  -> TypeContext
  -> Module
  -> ConcreteType
  -> ConcreteType
  -> TypedExpr
  -> [TypedExpr]
  -> TypedExpr
  -> IO TypedExpr
autoRefDeref ctx tctx mod toType fromType original temps ex = do
  let
    tryLvalue a b = do
      case tctxTemps tctx of
        Just v -> do
          tmp <- makeTmpVar (head $ tctxScopes tctx)
          let temp =
                (makeExprTyped
                  (VarDeclaration (Var tmp)
                                  (inferredType ex)
                                  (Just $ ex { tTemps = [] })
                  )
                  (inferredType ex)
                  (tPos ex)
                )
          autoRefDeref ctx tctx mod a b original (temp : temps)
            $ (makeExprTyped (Identifier (Var tmp) [])
                             (inferredType ex)
                             (tPos ex)
              ) { tIsLvalue = True
                }
  let finalizeResult ex = do
        case tctxTemps tctx of
          Just v -> do
            modifyIORef v (\val -> val ++ reverse temps)
        return ex
  toType   <- knownType ctx tctx mod toType
  fromType <- knownType ctx tctx mod fromType
  result   <- unify ctx tctx mod toType fromType
  case result of
    Just _ -> finalizeResult ex
    _      -> case (toType, fromType) of
      (TypePtr a, TypePtr b) -> autoRefDeref ctx tctx mod a b original temps ex
      (TypePtr a, b        ) -> if tIsLvalue ex
        then autoRefDeref ctx tctx mod a b original temps (addRef ex)
        else tryLvalue toType fromType
      (a, TypePtr (TypeBasicType BasicTypeVoid)) ->
        -- don't try to deref a void pointer
        return original
      (a, TypePtr b) ->
        autoRefDeref ctx tctx mod a b original temps (addDeref ex)
      (TypeBox tp params, b) -> do
        if tIsLvalue ex
          then do
            box <- makeBox ctx tp ex
            case box of
              Just x  -> finalizeResult x
              Nothing -> return original
          else tryLvalue toType fromType
      _ -> return original