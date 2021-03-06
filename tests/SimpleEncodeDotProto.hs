{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedLists #-}

module Main where

import           Test
import qualified TestImport
import           Proto3.Suite
import qualified Data.ByteString.Lazy as BL

outputMessage :: Message a => a -> IO ()
outputMessage msg =
  let encoded = toLazyByteString msg
  in putStrLn (show (BL.length encoded)) >> BL.putStr encoded

testCase1 :: IO ()
testCase1 =
  let trivial = Trivial 0xBADBEEF
  in outputMessage trivial

testCase2 :: IO ()
testCase2 =
  do outputMessage (MultipleFields 1.125 1e9 0x1135 0x7FFAFABADDEAFFA0 "Goodnight moon" False)

testCase3 :: IO ()
testCase3 =
  do outputMessage (WithEnum (Enumerated (Right WithEnum_TestEnumENUM1)))
     outputMessage (WithEnum (Enumerated (Right WithEnum_TestEnumENUM2)))
     outputMessage (WithEnum (Enumerated (Right WithEnum_TestEnumENUM3)))
     outputMessage (WithEnum (Enumerated (Left 0xABABABAB)))

testCase4 :: IO ()
testCase4 =
  do let nested = WithNesting_Nested "testCase4 nestedField1" 0xABCD
     outputMessage (WithNesting (Just nested))
     outputMessage (WithNesting Nothing)

testCase5 :: IO ()
testCase5 =
  do let nested1 = WithNestingRepeated_Nested "testCase5 nestedField1" 0xDCBA [1, 1, 2, 3, 5] [0xB, 0xABCD, 0xBADBEEF, 0x10203040]
         nested2 = WithNestingRepeated_Nested "Hello world" 0x7FFFFFFF [0, 0, 0] []
         nested3 = WithNestingRepeated_Nested "" 0x0 [] []

     outputMessage (WithNestingRepeated [nested1, nested2, nested3])
     outputMessage (WithNestingRepeated [])

testCase6 :: IO ()
testCase6 =
  do let nested1 = WithNestingRepeatedInts_NestedInts 636513 619021
         nested2 = WithNestingRepeatedInts_NestedInts 423549 687069
         nested3 = WithNestingRepeatedInts_NestedInts 545506 143731
         nested4 = WithNestingRepeatedInts_NestedInts 193605 385360
     outputMessage (WithNestingRepeatedInts [nested1])
     outputMessage (WithNestingRepeatedInts [])
     outputMessage (WithNestingRepeatedInts [nested1, nested2, nested3, nested4])

testCase7 :: IO ()
testCase7 =
  do outputMessage (WithRepetition [])
     outputMessage (WithRepetition [1..10000])

testCase8 :: IO ()
testCase8 =
  do outputMessage (WithFixedTypes 0 0 0 0)
     outputMessage (WithFixedTypes maxBound maxBound maxBound maxBound)
     outputMessage (WithFixedTypes minBound minBound minBound minBound)

testCase9 :: IO ()
testCase9 =
  do outputMessage (WithBytes "\x00\x00\x00\x01\x02\x03\xFF\xFF\x0\x1"
                              ["", "\x01", "\xAB\xBAhello", "\xBB"])
     outputMessage (WithBytes "Hello world" [])
     outputMessage (WithBytes "" ["Hello", "\x00world", "\x00\x00"])
     outputMessage (WithBytes "" [])

testCase10 :: IO ()
testCase10 =
  do outputMessage (WithPacking [] [])
     outputMessage (WithPacking [100, 2000, 300, 4000, 500, 60000, 7000] [])
     outputMessage (WithPacking [] [100, 2000, 300, 4000, 500, 60000, 7000])
     outputMessage (WithPacking [1, 2, 3, 4, 5] [5, 4, 3, 2, 1])

testCase11 :: IO ()
testCase11 =
  do outputMessage (AllPackedTypes [] [] [] [] [] [] [] [] [] [])
     outputMessage (AllPackedTypes [1] [2] [3] [4] [5] [6] [7] [8] [9] [10])
     outputMessage (AllPackedTypes [1] [2] [-3] [-4] [5] [6] [-7] [-8] [-9] [-10])
     outputMessage (AllPackedTypes [1..10000] [1..10000] [1..10000] [1..10000] [1..10000] [1..10000] [1,1.125..10000] [1,1.125..10000] [1..10000] [1..10000])

testCase12 :: IO ()
testCase12 =
  do outputMessage (OutOfOrderFields [] "" maxBound [])
     outputMessage (OutOfOrderFields [1,7..100] "This is a test" minBound ["This", "is", "a", "test"])

testCase13 :: IO ()
testCase13 =
  do outputMessage (ShadowedMessage "name" 0x7DADBEEF)
     outputMessage (MessageShadower (Just (MessageShadower_ShadowedMessage "name" "string value")) "another name")
     outputMessage (MessageShadower_ShadowedMessage "another name" "another string")

testCase14 :: IO ()
testCase14 =
  outputMessage (WithQualifiedName (Just (ShadowedMessage "int value" 42))
                                   (Just (MessageShadower_ShadowedMessage "string value" "hello world")))

testCase15 :: IO ()
testCase15 =
  outputMessage (TestImport.WithNesting { TestImport.withNestingNestedMessage1 =
                                            Just (TestImport.WithNesting_Nested { TestImport.withNesting_NestedNestedField1 = 1
                                                                                , TestImport.withNesting_NestedNestedField2 = 2 })
                                        , TestImport.withNestingNestedMessage2 = Nothing })

testCase16 :: IO ()
testCase16 =
  outputMessage (UsingImported { usingImportedImportedNesting =
                                   Just (TestImport.WithNesting
                                          (Just (TestImport.WithNesting_Nested 1 2))
                                          (Just (TestImport.WithNesting_Nested 3 4)))
                               , usingImportedLocalNesting =
                                   Just (WithNesting (Just (WithNesting_Nested "field" 0xBEEF))) })

main :: IO ()
main = do testCase1
          testCase2
          testCase3
          testCase4
          testCase5
          testCase6
          testCase7
          testCase8
          testCase9
          testCase10
          testCase11
          testCase12
          testCase13
          testCase14

          -- Tests using imported messages
          testCase15
          testCase16

          outputMessage (MultipleFields 0 0 0 0 "All tests complete" False)
