{-# LANGUAGE BangPatterns          #-}
{-# LANGUAGE CPP                   #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE TupleSections         #-}
{-# LANGUAGE TypeFamilies          #-}

import           Control.Monad ( foldM )
import           Control.Monad.Random ( MonadRandom, getRandomR )

#if __GLASGOW_HASKELL__ < 800
import           Data.List ( unfoldr )
#else
import           Data.List ( cycle, unfoldr )
#endif
import           Data.Semigroup ( (<>) )

import qualified Numeric.LinearAlgebra.Static as SA

import           Options.Applicative

import           Grenade
import           Grenade.Recurrent

-- The defininition for our simple recurrent network.
-- This file just trains a network to generate a repeating sequence
-- of 0 0 1.
--
-- The F and R types are Tagging types to ensure that the runner and
-- creation function know how to treat the layers.
type R = Recurrent

type RecNet = RecurrentNetwork '[ R (LSTM 1 4), R (LSTM 4 1)]
                               '[ 'D1 1, 'D1 4, 'D1 1 ]

type RecInput = RecurrentInputs '[ R (LSTM 1 4), R (LSTM 4 1)]

randomNet :: MonadRandom m => m (RecNet, RecInput)
randomNet = randomRecurrent

netTest :: MonadRandom m => RecNet -> RecInput -> LearningParameters -> Int -> m (RecNet, RecInput)
netTest net0 i0 rate iterations =
    foldM trainIteration (net0,i0) [1..iterations]
  where
    trainingCycle = cycle [c 0, c 0, c 1]

    trainIteration (net, io) _ = do
      dropping <- getRandomR (0, 2)
      count    <- getRandomR (5, 30)
      let t     = drop dropping trainingCycle
      let example = ((,Nothing) <$> take count t) ++ [(t !! count, Just $ t !! (count + 1))]
      return $ trainEach net io example

    trainEach !nt !io !ex = trainRecurrent rate nt io ex

data FeedForwardOpts = FeedForwardOpts Int LearningParameters

feedForward' :: Parser FeedForwardOpts
feedForward' = FeedForwardOpts <$> option auto (long "examples" <> short 'e' <> value 40000)
                               <*> (LearningParameters
                                    <$> option auto (long "train_rate" <> short 'r' <> value 0.01)
                                    <*> option auto (long "momentum" <> value 0.9)
                                    <*> option auto (long "l2" <> value 0.0005)
                                    )

generateRecurrent :: RecNet -> RecInput -> S ('D1 1) -> [Int]
generateRecurrent n s i =
  unfoldr go (s, i)
    where
  go (x, y) =
    do let (ns, o) = runRecurrent n x y
           o'      = heat o
       Just (o', (ns, fromIntegral o'))

  heat :: S ('D1 1) -> Int
  heat x = case x of
    (S1D v) -> round (SA.mean v)

main :: IO ()
main = do
    FeedForwardOpts examples rate <- execParser (info (feedForward' <**> helper) idm)
    putStrLn "Training network..."

    (net0, i0)              <- randomNet
    (trained, bestInput)    <- netTest net0 i0 rate examples

    let results = generateRecurrent trained bestInput (c 1)

    print . take 50 . drop 100 $ results

c :: Double -> S ('D1 1)
c = S1D . SA.konst
