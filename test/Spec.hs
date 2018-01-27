import Control.Batch
import Control.Concurrent.STM
import Control.Monad
import Data.IORef
import Data.Time.TimeSpan

import Test.Hspec


main :: IO ()
main = hspec spec

spec :: Spec
spec =
    describe "BatchJobs" $
    do it "batch job is processed on termination" $
           do outVar <- newIORef []
              let cfg =
                      Batch
                      { b_runEveryItems = Nothing
                      , b_runAfterTimeout = Nothing
                      , b_maxQueueLength = Nothing
                      , b_runBatch = \x -> writeIORef outVar x
                      }
              withBatchRunner cfg $ \hdl ->
                  do bh_enqueue hdl True
                     bh_enqueue hdl False
              readIORef outVar `shouldReturn` [True, False]
       it "batch jobs processes when N items reached" $
           do outVar <- atomically $ newTVar []
              let cfg =
                      Batch
                      { b_runEveryItems = Just 5
                      , b_runAfterTimeout = Nothing
                      , b_maxQueueLength = Nothing
                      , b_runBatch =
                              \x -> atomically $ modifyTVar' outVar (++x)
                      }
              withBatchRunner cfg $ \hdl ->
                  do replicateM_ 5 $ bh_enqueue hdl True
                     out <-
                         atomically $
                         do x <- readTVar outVar
                            when (length x /= 5) retry
                            pure x
                     out `shouldBe` [True, True, True, True, True]
       it "batch jobs processes when timeout reached" $
           do outVar <- atomically $ newTVar []
              let cfg =
                      Batch
                      { b_runEveryItems = Nothing
                      , b_runAfterTimeout = Just (seconds 1)
                      , b_maxQueueLength = Nothing
                      , b_runBatch =
                              \x -> atomically $ modifyTVar' outVar (++x)
                      }
              withBatchRunner cfg $ \hdl ->
                  do replicateM_ 5 $ bh_enqueue hdl True
                     out <-
                         atomically $
                         do x <- readTVar outVar
                            when (length x /= 5) retry
                            pure x
                     out `shouldBe` [True, True, True, True, True]
