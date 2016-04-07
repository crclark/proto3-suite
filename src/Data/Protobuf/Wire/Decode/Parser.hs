{-# LANGUAGE RankNTypes #-}
--TODO: are these really needed for `instance Integral a => Parsable a`?
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}

module Data.Protobuf.Wire.Decode.Parser (
Parser,
-- * General functions
parse,

-- * Combinators
require,
requireMsg,
one,
repeatedUnpacked,
parseEmbedded,

-- * Basic types
ProtobufParsable(..),
Fixed(..),
field,
embedded
) where

import           Control.Applicative
import           Control.Monad.Except
import           Control.Monad.Loops (whileJust)
import           Control.Monad.Reader
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import           Data.Functor.Identity(runIdentity)
import qualified Data.Map.Strict as M
import           Data.Maybe (catMaybes, isNothing)
import           Data.Protobuf.Wire.Decode.Internal
import           Data.Protobuf.Wire.Shared
import           Data.Serialize.Get(runGet, getWord32le, getWord64le)
import           Data.Serialize.IEEE754(getFloat32le, getFloat64le)
import           Data.Text.Lazy (Text)
import           Data.Text.Lazy.Encoding (decodeUtf8')
import           Data.Int (Int32, Int64)
import           Data.Word (Word32, Word64)

type Parser a = ReaderT (M.Map FieldNumber [ParsedField]) (Except String) a

parse :: Parser a -> B.ByteString -> Either String a
parse parser bs = do
  tuples <- parseTuples bs
  result <- runIdentity $ runExceptT $ runReaderT parser tuples
  return result

-- |
-- = Decoding 'ParsedField'
-- It is assumed that decisions about how to handle missing data will be handled
-- at a higher level, so our results are in 'Maybe', rather than erroring out.
-- To comply with the protobuf spec, if there are multiple fields with the same
-- field number, this will always return the last one. While this is worst case
-- O(n), in practice the worst case will only happen when a field in the .proto
-- file has been changed from singular to repeated, but the deserializer hasn't
-- been made aware of the change.

parsedField :: FieldNumber -> Parser (Maybe ParsedField)
parsedField fn = do
  currMap <- ask
  let pfs = M.lookup fn currMap
  case pfs of
    Just xs@(_:_) -> return $ Just $ last xs
    _ -> return Nothing

-- |
-- Consumes all fields with the given field number. This is primarily for
-- unpacked repeated fields. This is also useful for parsing
-- embedded messages, where the spec says that if more than one instance of an
-- embedded message for a given field number is present in the outer message,
-- then they must all be merged.
parsedFields :: FieldNumber -> Parser [ParsedField]
parsedFields fn = do
  currMap <- ask
  let pfs = M.lookup fn currMap
  case pfs of
    Just xs -> return xs
    Nothing -> return []

-- |
-- Requires a field to be present.
require :: Parser (Maybe a) -> Parser a
require p = do
  result <- p
  case result of
    Nothing -> throwError "Required field missing."
    Just x -> return x

-- |
-- Requires a field to be present, with custom error message.
requireMsg :: Parser (Maybe a) -> String -> Parser a
requireMsg p str = do
  result <- p
  case result of
    Nothing -> throwError str
    Just x -> return x

throwWireTypeError :: Show a => String -> a -> Parser b
throwWireTypeError expected wrong =
  throwError $ "Wrong wiretype. Expected " ++ expected ++
               " but got " ++ show wrong

throwCerealError :: String -> String -> Parser b
throwCerealError expected cerealErr =
  throwError $ "Failed to parse contents of " ++ expected ++ " field. "
               ++ "Error from cereal was: " ++ cerealErr

parseVarInt :: Integral a => ParsedField -> Parser a
parseVarInt (VarintField i) = return $ fromIntegral i
parseVarInt wrong = throwWireTypeError "varint" wrong

parsePackedVarInt :: Integral a => ParsedField -> Parser [a]
parsePackedVarInt (LengthDelimitedField bs) =
  case runGet (many getBase128Varint) bs of
    Left e -> throwCerealError "packed varints" e
    Right xs -> return $ map fromIntegral xs
parsePackedVarInt wrong = throwWireTypeError "packed varints" wrong

parseFixed32 :: Integral a => ParsedField -> Parser a
parseFixed32 (Fixed32Field bs) =
  case runGet getWord32le bs of
    Left e -> throwCerealError "fixed32" e
    Right i -> return $ fromIntegral i
parseFixed32 wrong = throwWireTypeError "fixed32" wrong

parseFixed32Float :: ParsedField -> Parser Float
parseFixed32Float (Fixed32Field bs) =
  case runGet getFloat32le bs of
    Left e -> throwCerealError "fixed32" e
    Right f -> return f
parseFixed32Float wrong = throwWireTypeError "fixed32" wrong

parseFixed64 :: Integral a => ParsedField -> Parser a
parseFixed64 (Fixed64Field bs) =
  case runGet getWord64le bs of
    Left e -> throwCerealError "fixed64" e
    Right i -> return $ fromIntegral i
parseFixed64 wrong = throwWireTypeError "fixed64" wrong

parseFixed64Double :: ParsedField -> Parser Double
parseFixed64Double (Fixed64Field bs) =
  case runGet getFloat64le bs of
    Left e -> throwCerealError "fixed64" e
    Right f -> return f
parseFixed64Double wrong = throwWireTypeError "fixed64" wrong

parseText :: ParsedField -> Parser Text
parseText (LengthDelimitedField bs) =
  case decodeUtf8' $ BL.fromStrict bs of
    Left err -> throwError $ "Failed to decode UTF-8: " ++ show err
    Right txt -> return txt
parseText wrong = throwWireTypeError "string" wrong

-- | Create a parser for embedded fields from a message parser. This can
-- be used to easily create an instance of 'ProtobufParsable' for a user-defined
-- type.
parseEmbedded :: Parser a -> ParsedField -> Parser a
parseEmbedded parser (LengthDelimitedField bs) =
  case parse parser bs of
    Left err -> throwError $ "Failed to parse embedded message: " ++ show err
    Right result -> return result
parseEmbedded _ wrong = throwWireTypeError "embedded" wrong

-- |
-- Specify that one value is expected from this field. Used to ensure that we
-- return the last value with the given field number in the message, in
-- compliance with the protobuf standard.
one :: (ParsedField -> Parser a) -> FieldNumber -> Parser (Maybe a)
one rawParser fn = parsedField fn >>= mapM rawParser

newtype Fixed a = Fixed {getFixed :: a} deriving (Show, Eq, Ord)

class ProtobufParsable a where
  fromField :: ParsedField -> Parser a

instance ProtobufParsable Int32 where
  fromField = parseVarInt

instance ProtobufParsable Word32 where
  fromField = parseVarInt

instance ProtobufParsable Int64 where
  fromField = parseVarInt

instance ProtobufParsable Word64 where
  fromField = parseVarInt

instance ProtobufParsable (Fixed Word32) where
  fromField = liftM (liftM Fixed) parseFixed32

instance ProtobufParsable (Fixed Int32) where
  fromField = liftM (liftM Fixed) parseFixed32

instance ProtobufParsable (Fixed Word64) where
  fromField = liftM (liftM Fixed) parseFixed64

instance ProtobufParsable (Fixed Int64) where
  fromField = liftM (liftM Fixed) parseFixed64

instance ProtobufParsable Float where
  fromField = parseFixed32Float

instance ProtobufParsable Double where
  fromField = parseFixed64Double

instance ProtobufParsable Text where
  fromField = parseText

field :: ProtobufParsable a => FieldNumber -> Parser (Maybe a)
field = one fromField

-- | Parses an embedded message. The ProtobufMerge constraint is to satisfy the
-- specification, which states that if the field number of the embedded message
-- is repeated (i.e., multiple embedded messages are provided), the messages
-- are merged.
--
-- Specifically, the protobufs specification states
-- that the latter singular fields should overwrite the former, singular
-- embedded messages are merged, and repeated fields are concatenated.

-- TODO: it's currently possible for someone to try to decode embedded fields
-- incorrectly by just binding 'parser' without using 'embedded', causing an
-- error at runtime. Can we do anything to prevent that with the types?
embedded :: ProtobufMerge a => Parser a -> FieldNumber -> Parser (Maybe a)
embedded parser fn = do
  pfs <-parsedFields fn
  parsedResults <- mapM (parseEmbedded parser) pfs
  case parsedResults of
    [] -> return Nothing
    xs -> return $ Just $ foldl1 protobufMerge xs

repeatedUnpacked :: ProtobufParsable a => FieldNumber -> Parser [a]
repeatedUnpacked fn = parsedFields fn >>= mapM fromField
