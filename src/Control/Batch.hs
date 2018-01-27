{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE StrictData #-}
module Control.Batch
    ( Batch(..)
    , BatchHandle(..)
    , withBatchRunner
    )
where

import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Exception.Lifted
import Control.Monad
import Control.Monad.Base
import Control.Monad.Trans.Control
import Data.Time.TimeSpan
import qualified Control.Concurrent.Async.Lifted as L

data Batch v m
    = Batch
    { b_runEveryItems :: Maybe Int
      -- ^ flush in memory items ever N items for processing
    , b_runAfterTimeout :: Maybe TimeSpan
      -- ^ flush after item stuck in queue for longer than this
    , b_maxQueueLength :: Maybe Int
      -- ^ if more than N items are enqueued, block enqueueing
    , b_runBatch :: [v] -> m ()
      -- ^ function describing how batches should be processed
    }

data BatchHandle v m
    = BatchHandle
    { bh_enqueue :: v -> m ()
      -- ^ enqueue a new element
    }

withBatchRunner ::
    forall v m a. MonadBaseControl IO m
    => Batch v m -> (BatchHandle v m -> m a) -> m a
withBatchRunner batch go =
    do dummy <- liftBase $ async $ pure ()
       (queueVar, sizeVar, flushThreadVar, triggerVar, stopVar) <-
           liftBase $ atomically $
           (,,,,) <$> newTQueue <*> newTVar 0 <*> newTVar dummy <*> newTVar False <*> newTVar False
       let flusher :: m ()
           flusher =
               do shouldStop <-
                      liftBase $
                      atomically $
                      do x <- readTVar triggerVar
                         stop <- readTVar stopVar
                         unless (stop || x) retry
                         writeTVar triggerVar False
                         pure stop
                  drain <-
                      liftBase $
                      atomically $
                      do let readLoop !accum =
                                 do x <- tryReadTQueue queueVar
                                    case x of
                                      Nothing -> pure (reverse accum)
                                      Just v -> readLoop (v : accum)
                         readLoop []
                  b_runBatch batch drain
                  unless shouldStop flusher
           flush = writeTVar triggerVar True
           enqueue item =
               liftBase $
               do case b_maxQueueLength batch of
                    Just maxLen ->
                        atomically $
                        do totalSize <- readTVar sizeVar
                           when (totalSize > maxLen) retry
                    Nothing -> pure ()
                  waiter <-
                      async $
                      case b_runAfterTimeout batch of
                        Nothing -> pure ()
                        Just ts ->
                            do sleepTS ts
                               atomically flush
                  (oldFlushThread :: Async ()) <-
                      atomically $
                      do writeTQueue queueVar item
                         modifyTVar' sizeVar (+1)
                         totalSize <- readTVar sizeVar
                         oldFlush <- readTVar flushThreadVar
                         case b_runEveryItems batch of
                           Just x | totalSize >= x -> flush
                           _ -> pure ()
                         writeTVar flushThreadVar waiter
                         pure oldFlush
                  uninterruptibleCancel oldFlushThread
       flushThread <- L.async flusher
       let bh = BatchHandle enqueue
           cleanup =
               liftBase $
               do atomically $ writeTVar stopVar True >> flush
                  wait flushThread
       go bh `finally` cleanup
