{-# LANGUAGE ForeignFunctionInterface, UnliftedFFITypes, JavaScriptFFI, 
    CPP, MagicHash, FlexibleInstances, BangPatterns #-}

module GHCJS.Foreign ( ToJSString(..)
                     , FromJSString(..)
                     , mvarRef
                     , fromJSBool
                     , fromJSBool'
                     , toJSBool
                     , jsTrue
                     , jsFalse
                     , jsNull
                     , jsUndefined
                     , toArray
                     , newArray
                     , fromArray
                     , pushArray
                     , indexArray
                     , lengthArray
                     , newObj
                     , getProp
                     , getPropMaybe
                     , setProp
                     ) where

import           GHCJS.Types

import           GHC.Prim
import           GHC.Exts

import           Control.Applicative
import           Control.Concurrent.MVar
import qualified Data.Text as T
import           Foreign.Ptr
import           Unsafe.Coerce


import qualified Data.Text.Array as A

#ifdef __GHCJS__
foreign import javascript unsafe "$r = h$toStr($1,$2,$3);" js_toString :: Ref# -> Int# -> Int# -> Ref#
foreign import javascript unsafe "$r = h$fromStr($1); $r2 = h$ret1;" js_fromString :: Ref# -> Ptr ()
foreign import javascript unsafe "($1 === true) ? 1 : 0" js_fromBool :: JSBool -> Int#
foreign import javascript unsafe "$1 ? 1 : 0" js_isTruthy :: JSRef a -> Int#
foreign import javascript unsafe "$r = true"  js_true :: Int# -> Ref#
foreign import javascript unsafe "$r = false" js_false :: Int# -> Ref#
foreign import javascript unsafe "$r = null"  js_null :: Int# -> Ref#
foreign import javascript unsafe "$r = undefined"  js_undefined :: Int# -> Ref#
foreign import javascript unsafe "$r = []" js_emptyArray :: IO (JSArray a)
foreign import javascript unsafe "$r = {}" js_emptyObj :: IO (JSRef a)
foreign import javascript unsafe "$2.push($1)" js_push :: JSRef a -> JSArray a -> IO ()
foreign import javascript unsafe "$1.length" js_length :: JSArray a -> IO Int
foreign import javascript unsafe "$2[$1]" js_index :: Int -> JSArray a -> IO (JSRef a)
foreign import javascript unsafe "$2[$1]" js_getProp :: JSString -> JSRef a -> IO (JSRef b)
foreign import javascript unsafe "$3[$1] = $2" js_setProp :: JSString -> JSRef a -> JSRef b -> IO ()
#else
js_toString :: Ref# -> Int# -> Int# -> Ref#
js_toString = error "js_toString: only available in JavaScript"
js_fromString :: Ref# -> Ptr ()
js_fromString = error "js_fromString: only available in JavaScript"
js_fromBool :: JSBool -> Int#
js_fromBool = error "js_fromBool: only available in JavaScript"
js_isTruthy :: JSRef a -> Int#
js_isTruthy = error "js_isTruthy: only available in JavaScript"
js_true :: Int# -> Ref#
js_true = error "js_true: only available in JavaScript"
js_false :: Int# -> Ref#
js_false = error "js_false: only available in JavaScript"
js_null :: Int# -> Ref#
js_null = error "js_null: only available in JavaScript"
js_undefined :: Int# -> Ref#
js_undefined = error "js_undefined: only available in JavaScript"
js_emptyObj :: IO (JSRef a)
js_emptyObj = error "js_emptyObj: only available in JavaScript"
js_emptyArray :: IO (JSArray a)
js_emptyArray = error "js_emptyArr: only available in JavaScript"
js_push :: JSRef a -> JSArray a -> IO ()
js_push = error "js_push: only available in JavaScript"
js_length :: JSArray a -> IO Int
js_length = error "js_length: only available in JavaScript"
js_index :: Int -> JSArray a -> IO (JSRef a)
js_index = error "js_index: only available in JavaScript"
js_getProp :: JSString -> JSRef a -> IO (JSRef b)
js_getProp = error "js_getProp: only available in JavaScript"
js_setProp :: JSString -> JSRef a -> JSRef b -> IO ()
js_setProp = error "js_setProp: only available in JavaScript"
#endif

class ToJSString a where
  toJSString :: a -> JSString

class FromJSString a where
  fromJSString :: JSString -> a

instance ToJSString [Char] where
  toJSString = toJSString . T.pack
  {-# INLINE toJSString #-}

instance FromJSString [Char] where
  fromJSString = T.unpack . fromJSString
  {-# INLINE fromJSString #-}

instance ToJSString T.Text where
  toJSString t =
    let !(Text'' (Array'' b) (I# offset) (I# length)) = unsafeCoerce t
    in  mkRef (js_toString b offset length)
  {-# INLINE toJSString #-}

instance FromJSString T.Text where
  fromJSString (JSRef ref) =
    let !(Ptr' ba l) = ptrToPtr' (js_fromString ref)
    in  unsafeCoerce (Text' (Array' ba) 0 (I# l))
  {-# INLINE fromJSString #-}

instance ToJSString JSString where
  toJSString t = t
  {-# INLINE toJSString #-}

instance FromJSString JSString where
  fromJSString t = t
  {-# INLINE fromJSString #-}

instance IsString JSString where
  fromString = toJSString
  {-# INLINE fromString #-}

fromJSBool :: JSBool -> Bool
fromJSBool b = case js_fromBool b of
                 1# -> True
                 _  -> False
{-# INLINE fromJSBool #-}

toJSBool :: Bool -> JSBool
toJSBool True = jsTrue
toJSBool _    = jsFalse
{-# INLINE toJSBool #-}

-- check whether a reference is `truthy' in the JavaScript sense
fromJSBool' :: JSRef a -> Bool
fromJSBool' b = case js_isTruthy b of
                  1# -> True
                  _  -> False
{-# INLINE fromJSBool' #-}

jsTrue :: JSBool
jsTrue = mkRef (js_true 0#)

jsFalse :: JSBool
jsFalse = mkRef (js_false 0#)


jsNull :: JSRef a
jsNull = mkRef (js_null 0#)

jsUndefined :: JSRef a
jsUndefined = mkRef (js_undefined 0#)

mvarRef :: MVar a -> JSObject (MVar a)
mvarRef = unsafeCoerce

-- something that we can unsafeCoerce Text from
data Text' = Text'
    {-# UNPACK #-} !Array'           -- payload
    {-# UNPACK #-} !Int              -- offset
    {-# UNPACK #-} !Int              -- length

data Array' = Array' {
      aBA :: ByteArray#
    }

data Text'' = Text''
    {-# UNPACK #-} !Array''          -- payload
    {-# UNPACK #-} !Int              -- offset
    {-# UNPACK #-} !Int              -- length

data Array'' = Array'' {
      aRef :: Ref#
    }

-- same rep as Ptr Addr#, use this to get just the first field out
data Ptr' a = Ptr' ByteArray# Int#

ptrToPtr' :: Ptr a -> Ptr' b
ptrToPtr' = unsafeCoerce

ptr'ToPtr :: Ptr' a -> Ptr b
ptr'ToPtr = unsafeCoerce

toArray :: [JSRef a] -> IO (JSArray a)
toArray xs = do
  a <- js_emptyArray
  let go ys = case ys of
                (y:ys') -> js_push y a >> go ys'
                _       -> return ()
  go xs
  return a
{-# INLINE toArray #-}

pushArray :: JSRef b -> JSArray a -> IO ()
pushArray r arr = js_push (castRef r) arr
{-# INLINE pushArray #-}

fromArray :: JSArray a -> IO [JSRef a]
fromArray a = do
  l <- js_length a
  let go i | i < l     = (:) <$> js_index i a <*> go (i+1)
           | otherwise = return []
  go 0
{-# INLINE fromArray #-}

lengthArray :: JSArray a -> IO Int
lengthArray a = js_length a
{-# INLINE lengthArray #-}

indexArray :: Int -> JSArray a -> IO (JSRef a)
indexArray = js_index
{-# INLINE indexArray #-}

newArray :: IO (JSArray a)
newArray = js_emptyArray
{-# INLINE newArray #-}

newObj :: IO (JSRef a)
newObj = js_emptyObj
{-# INLINE newObj #-}

getProp :: ToJSString a => a -> JSRef b -> IO (JSRef c)
getProp p o = js_getProp (toJSString p) o
{-# INLINE getProp #-}

getPropMaybe :: ToJSString a => a -> JSRef b -> IO (Maybe (JSRef c))
getPropMaybe p o = do
  p' <- js_getProp (toJSString p) o
  if isUndefined p' then return Nothing else return (Just p')
{-# INLINE getPropMaybe #-}

setProp :: ToJSString a => a -> JSRef b -> JSRef c -> IO ()
setProp p v o = js_setProp (toJSString p) v o
{-# INLINE setProp #-}
