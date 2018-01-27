# batch

[![CircleCI](https://circleci.com/gh/agrafix/batch.svg?style=svg)](https://circleci.com/gh/agrafix/batch)

Simplify queuing up data and processing it in batch.

```haskell
import Control.Batch
import Control.Concurrent.STM
import Control.Monad

example :: IO ()
example =
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
```
