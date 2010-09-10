> module Antioch.Statistics where

> import Antioch.DateTime   (fromGregorian, DateTime, addMinutes', diffMinutes')
> import Antioch.DateTime   (toGregorian')
> import Antioch.Generators
> import Antioch.Types
> import Antioch.Score
> import Antioch.Utilities  (rad2hrs, rad2deg, utc2lstHours, dt2semester) 
> import Antioch.Weather
> import Antioch.TimeAccounting
> import Antioch.Debug
> import Antioch.ReceiverTemperatures
> import Control.Arrow      ((&&&), second)
> import Data.Array
> import Data.Fixed         (div')
> import Data.Function      (on)
> import Data.List
> import Data.Time.Clock
> import Data.Maybe         (fromMaybe, isJust, fromJust)
> import Graphics.Gnuplot.Simple
> import System.Random      (getStdGen)
> import Test.QuickCheck    (generate, choose)

> freqRange :: [Float]
> freqRange = [0.0..120.0] 

> raRange :: [Float]
> raRange = [0..24]

> decRange :: [Float]
> decRange = [-40..90]

> bandRange :: [Band]
> bandRange = [P .. W]

To Do List (port from Statistics.py):

   * used in error bars (used in plotObsEffVsFreq and plotMeanObsEffVsFreq)
      Stats done.  Still need to plot.
       * frequency mean
       * obs eff mean and standard deviation
   * historical bad fixed frequency and obs eff true (plotMeanObsEffVsFreq)
   * historical bad window frequency and obs eff true (plotMeanObsEffVsFreq)
   * true historical observing scores
   * historical pressure vs lst
      Need historical pressures

> compareWindowPeriodEfficiencies :: [(Window, Maybe Period, Period)] -> IO [((Period, Float), (Period, Float))]
> compareWindowPeriodEfficiencies winfo = do
>     dpsEffs <- historicalSchdMeanObsEffs dps
>     cpsEffs <- historicalSchdMeanObsEffs cps
>     return $ zip (zip cps cpsEffs) (zip dps dpsEffs)
>   where
>     dps = concat $ map (\(w, mc, d) -> if isJust mc then [d] else []) winfo 
>     cps = concat $ map (\(w, mc, d) -> if isJust mc then [fromJust mc] else []) winfo 
 
> calcMeanWindowEfficiencies :: [((Period, Float), (Period, Float))] -> (Float, Float)
> calcMeanWindowEfficiencies wps = (meanEff cpsEffs, meanEff dpsEffs)
>   where
>     cpsEffs = fst . unzip $ wps 
>     dpsEffs = snd . unzip $ wps 
>     meanEff psEffs = (sum $ map (\(p, e) -> (fromIntegral . duration $ p) * e) psEffs) / (sum $ map (fromIntegral . duration . fst) psEffs)

> fracObservedTimeByDays :: [Session] -> [Period] -> [(Float, Float)]
> fracObservedTimeByDays _  [] = []
> fracObservedTimeByDays [] _  = []
> fracObservedTimeByDays ss ps = map fracObservedTime days
>   where
>     days = [0 .. (numDays + 1)]
>     --numDays = ((diffMinutes' lastDt firstDt) `div` (60 * 24)) 
>     --firstDt = startTime $ head ps
>     --lastDt  = startTime $ last ps
>     firstDt = fst $ getPeriodRange ps
>     numDays = snd $ getPeriodRange ps
>     total = totalSessionHrs ss
>     fracObservedTime day = (fromIntegral day,(total - (observed day)) / total)
>     observed day = getTotalHours $ observedPeriods day
>     observedPeriods day = takeWhile (\p -> startTime p < (toDt day)) ps
>     toDt day = (day * 24 * 60) `addMinutes'` firstDt

> fracObservedTimeByDays' :: [Session] -> [Period] -> DateTime -> Int -> [(Float, Float)]
> fracObservedTimeByDays' _  [] _ _ = []
> fracObservedTimeByDays' [] _  _ _ = []
> fracObservedTimeByDays' ss ps start numDays = map fracObservedTime days
>   where
>     days = [0 .. (numDays + 1)]
>     --numDays = ((diffMinutes' lastDt firstDt) `div` (60 * 24)) 
>     --firstDt = startTime $ head ps
>     --lastDt  = startTime $ last ps
>     total = totalSessionHrs ss
>     fracObservedTime day = (fromIntegral day,(total - (observed day)) / total)
>     observed day = getTotalHours $ observedPeriods day
>     observedPeriods day = takeWhile (\p -> startTime p < (toDt day)) ps
>     toDt day = (day * 24 * 60) `addMinutes'` start

> getPeriodRange :: [Period] -> (DateTime, Int)
> getPeriodRange ps = (firstDt, numDays)
>   where
>     numDays = ((diffMinutes' lastDt firstDt) `div` (60 * 24)) 
>     firstDt = startTime $ head ps
>     lastDt  = startTime $ last ps

Remaining Time here refers to the remaining time used in the pressure
factor calculation.  See Score.initBins'.
Given a pool of sessions, a start time, and a number of days, produces:
[(day #, sum of 'remaining time' for that day #)]; 
TBF: this was created in an attempt to reproduce the components of the 
preassure plots, but I believe that they were deprecated because we really
need to use the trace to do this correctly.

> remainingTimeByDays :: [Session] -> DateTime -> Int -> [(Float, Float)]
> remainingTimeByDays [] _ _ = []
> remainingTimeByDays ss start numDays = map fracRemainingTime days
>   where
>     days = [0 .. (numDays + 1)]
>     fracRemainingTime day = (fromIntegral day, totalRemaining day)
>     --totalRemaining day = fractionalHours . sum $ map (rho (toDt day)) $ ss 
>     totalRemaining day = fractionalHours . sum $ map (remaining (toDt day)) $ ss 
>     toDt day = (day * 24 * 60) `addMinutes'` start
>     remaining dt s = (rho dt s) + (sPastS dt s)
>     -- this is simply cut and paste from Score.initBins'
>     rho dt s
>       | isActive s dt = max 0 (sFutureS dt s)
>       | otherwise  = 0
>     -- here, Scomplete -> sTerminated to avoid looking at sAvailT (==0)
>     isActive s dt = (isAuthorized s dt) && (not . sTerminated $ s)
>     isAuthorized s dt = (semester . project $ s) <= (dt2semester dt)

Given a pool of sessions, a start time, and a number of days, produces:
[(day #, sum of SPastS for that day #)]; 
TBF: this was created in an attempt to reproduce the components of the 
preassure plots, but I believe that they were deprecated because we really
need to use the trace to do this correctly.
See Also Score.initBins'.

> pastSemesterTimeByDays :: [Session] -> DateTime -> Int -> [(Float, Float)]
> pastSemesterTimeByDays [] _ _ = []
> pastSemesterTimeByDays ss start numDays = map fracSemesterTime days
>   where
>     days = [0 .. (numDays + 1)]
>     fracSemesterTime day = (fromIntegral day, totalSemester day)
>     totalSemester day = fractionalHours . sum $ map (sPastS (toDt day)) $ ss 
>     toDt day = (day * 24 * 60) `addMinutes'` start

> historicalSchdObsEffs ps = historicalSchdFactors ps observingEfficiency
> historicalSchdAtmEffs ps = historicalSchdFactors ps atmosphericEfficiency
> historicalSchdTrkEffs ps = historicalSchdFactors ps trackingEfficiency
> historicalSchdSrfEffs ps = historicalSchdFactors ps surfaceObservingEfficiency

> historicalSchdMeanObsEffs ps = historicalSchdMeanFactors ps observingEfficiency
> historicalSchdMeanAtmEffs ps = historicalSchdMeanFactors ps atmosphericEfficiency
> historicalSchdMeanTrkEffs ps = historicalSchdMeanFactors ps trackingEfficiency
> historicalSchdMeanSrfEffs ps = historicalSchdMeanFactors ps surfaceObservingEfficiency

For the given list of periods, return the concatanated list of results
for the given scoring factor that the periods' sessions had when they
were scheduled.  Currently this is used to check all the schedules scores
for normalicy (0 < score < 1).

> historicalSchdFactors :: [Period] -> ScoreFunc -> IO [Float]
> historicalSchdFactors ps sf = do
>   w <- getWeather Nothing
>   fs <- mapM (periodSchdFactors' w) ps
>   return $ concat fs
>     where
>       periodSchdFactors' w p = periodSchdFactors p sf w

This function can be useful if invalid scores are encountered, and the 
offending period/session/project needs to be revealed.

> historicalSchdFactorsDebug :: [Period] -> ScoreFunc -> IO [(Float,Period)]
> historicalSchdFactorsDebug ps sf = do
>   w <- getWeather Nothing
>   fs <- mapM (periodSchdFactors' w) ps
>   return $ concat $ zipWith (\x y -> map (\y' -> (y', x)) y) ps fs --concat fs
>     where
>       periodSchdFactors' w p = periodSchdFactors p sf w

For the given list of periods, returns the mean of the scoring factor given
at the time that the periods' session was scheduled.  In other words, this
*almost* represents the exact scoring result for the periods' session at the
time the periods were scheduled (see TBF).
TBF: the use of mean' might cause misunderstandings, since pack zero's out
the first quarter.  We should be using the weighted average found in Score.

> historicalSchdMeanFactors :: [Period] -> ScoreFunc -> IO [Float]
> historicalSchdMeanFactors ps sf = do
>   w <- getWeather Nothing
>   fs <- mapM (periodSchdFactors' w) ps
>   return $ map mean' fs
>     where
>       periodSchdFactors' w p = periodSchdFactors p sf w

For the given period and scoring factor, returns the value of that scoring
factor at each quarter of the period *for the time it was scheduled*.
In other words, recreates the conditions for which this period was scheduled.

> periodSchdFactors :: Period -> ScoreFunc -> Weather -> IO [Float]
> periodSchdFactors p sf w = do
>   rt <- getReceiverTemperatures
>   -- this step is key to ensure we use the right forecasts
>   w' <- newWeather w $ Just $ pForecast p
>   fs <- runScoring w' rs rt $ factorPeriod p sf  
>   return $ map eval fs
>     where
>   rs = [] -- TBF: how to pass this down?

> sessionDecFreq :: [Session] -> [(Float, Radians)]
> sessionDecFreq = dec `vs` frequency

> periodDecFreq :: [Period] -> [(Float, Radians)]
> periodDecFreq = promote sessionDecFreq

> sessionDecRA :: [Session] -> [(Radians, Radians)]
> sessionDecRA = dec `vs` ra

> periodDecRA :: [Period] -> [(Radians, Radians)]
> periodDecRA = promote sessionDecRA

> sessionRA :: [Session] -> [(Radians, Float)]
> sessionRA = count (rad2hrs . ra) raRange

> periodRA :: [Period] -> [(Radians, Float)]
> periodRA = promote sessionRA

> sessionRAHrs :: [Session] -> [(Radians, Float)]
> sessionRAHrs =  histogram raRange . ((fractionalHours . sAllottedT) `vs` (rad2hrs . ra))

> periodRAHrs :: [Period] -> [(Radians, Float)]
> periodRAHrs = histogram raRange . ((fractionalHours . duration) `vs` (rad2hrs . ra . session))

> fractionalHours min = fromIntegral min / 60.0

> sessionDec :: [Session] -> [(Radians, Float)]
> sessionDec = count (rad2deg . dec) decRange --[-40..90]

> periodDec :: [Period] -> [(Radians, Float)]
> periodDec = promote sessionDec

> sessionDecHrs :: [Session] -> [(Radians, Float)]
> sessionDecHrs =  histogram decRange . ((fractionalHours . sAllottedT) `vs` (rad2deg . dec))

> periodDecHrs :: [Period] -> [(Float, Float)]
> periodDecHrs = histogram decRange . ((fractionalHours . duration) `vs` (rad2deg . dec . session)) 

> sessionFreq :: [Session] -> [(Float, Minutes)]
> --sessionFreq = histogram [1.0..50.0] . (sAllottedT `vs` frequency)
> sessionFreq = histogram freqRange . (sAllottedT `vs` frequency)

> sessionFreqHrs :: [Session] -> [(Float, Float)]
> sessionFreqHrs = histogramToHours . sessionFreq

> --statsFreqMinMax = (realToFrac . minimum $ statsFreqRange, realToFrac . maximum $ statsFreqRange)

> periodFreq :: [Period] -> [(Float, Minutes)]
> periodFreq =
>     histogram freqRange . (duration `vs` (frequency . session))

> periodFreqHrs :: [Period] -> [(Float, Float)]
> periodFreqHrs = histogramToHours . periodFreq

> periodFreqBackupHrs :: [Period] -> [(Float, Float)]
> periodFreqBackupHrs = histogramToHours . periodFreq . filter pBackup

Produces a histogram of the ratio of the canceled to scheduled hours by 
a special frequency bin.  Note that the periods passed in are what
was observed, so the original schedule is the join of the non-backup observed
periods with those that were canceled.

> periodCanceledFreqRatio :: [Period] -> [Trace] ->  [(Float, Float)]
> periodCanceledFreqRatio ps trace = zipWith3 canceledRatio freqBinMidpoints (canceledFreqHrs trace frequencyBins) (scheduledFreqHrs ps trace frequencyBins)
>   where
>     canceledRatio midPoint (_, canceled) (_, 0.0)       = (midPoint, 0.0)
>     canceledRatio midPoint (_, canceled) (_, scheduled) = (midPoint, canceled / scheduled)

> freqBinMidpoints :: [Float]
> freqBinMidpoints = midPoints (0.0 : frequencyBins)

> midPoints    :: [Float] -> [Float]
> midPoints xs = [(x1 + x2) / 2.0 | (x1 : x2 : _) <- tails xs]

> scheduledFreqHrs :: [Period] -> [Trace] -> [Float] -> [(Float, Float)]
> scheduledFreqHrs ps trace bins = histogram bins . ((fractionalHours . duration) `vs` (frequency . session)) $ getScheduledPeriods ps trace 

> getScheduledPeriods :: [Period] -> [Trace] -> [Period]
> getScheduledPeriods observed trace = observed' ++ canceled
>   where
>     canceled  = getCanceledPeriods trace
>     observed' = [p | p <- observed, not . pBackup $ p]

> canceledFreqHrs :: [Trace] -> [Float] -> [(Float, Float)]
> canceledFreqHrs trace bins = histogram bins . ((fractionalHours . duration) `vs` (frequency . session)) . getCanceledPeriods $ trace

> periodBackupFreqRatio :: [Period] -> [(Float, Float)]
> periodBackupFreqRatio ps = zipWith backupRatio (periodFreqHrsBinned ps) (periodFreqHrsBinned psBackups)
>   where
>     psBackups =  [p | p <- ps, pBackup p]
>     backupRatio obs backup = (fst obs, snd backup / snd obs)

> periodFreqHrsBinned :: [Period] -> [(Float, Float)]
> periodFreqHrsBinned = histogram frequencyBins . ((fractionalHours . duration) `vs` (frequency . session))

> histogramToHours :: [(Float, Minutes)] -> [(Float, Float)]
> histogramToHours =  map $ second fractionalHours

> sessionTP    :: [Period] -> [(Float, Int)]
> sessionTP ps = count f d ps
>   where
>     f = fractionalHours . duration
>     d = findDomain 1.0 . map f $ ps

Search the data to find an enumerable range bounding the input given a fixed step size.

> findDomain'      :: Real a => a -> [(a, b)] -> [a]
> findDomain' step = findDomain step . map fst

> findDomain         :: Real a => a -> [a] -> [a]
> findDomain step xs = [step * fromIntegral x | x <- [x1, x1+1 .. x2+1]]
>   where
>     [x1, x2] = map ((`div'` step) . ($ xs)) [minimum, maximum]

> sessionTPQtrs :: [Period] -> [(Minutes, Int)]
> sessionTPQtrs = count (duration) [0, quarter..(13*60)]


Counts how many sessions have a min duration for each quarter hour.
For randomly generated data, this should be a flat distribution.

> sessionMinDurationQtrs :: [Session] -> [(Minutes, Int)]
> sessionMinDurationQtrs = count (minDuration) [0, quarter..(13*60)]

> periodDuration :: [Period] -> [(Minutes, Minutes)]
> periodDuration = histogram [0, quarter..(13*60)] . (duration `vs` duration)


> sessionMinDuration :: [Session] -> [(Minutes, Minutes)]
> sessionMinDuration = histogram [0, quarter..(13*60)] . (minDuration `vs` minDuration)

What is the maximum amount of time that can be scheduled using the min duration.

> sessionMinDurMaxTime :: [Session] -> [(Minutes, Minutes)]
> sessionMinDurMaxTime = histogram [0, quarter..(13*60)] . (maxNumTPTime `vs` minDuration)
>   where
>     maxNumTPTime s = maxNumTPs s * minDuration s
>     maxNumTPs s = sAllottedT s `div` minDuration s

Example of scatter plot data w/ datetime:

> freqTime :: [Period] -> [(DateTime, Float)]
> freqTime = (frequency . session) `vs` startTime

Example of log histogram data:
Compare allocated hours by frequency to observed hours by frequency.

> periodBand :: [Period] -> [(Band, Float)]
> periodBand = histogram bandRange . ((fractionalHours . duration) `vs` (band . session))

> sessionBand :: [Session] -> [(Band, Float)]
> sessionBand = histogram bandRange . ((fractionalHours . sAllottedT) `vs` band)

> sessionAvBand :: [Session] -> [(Band, Float)]
> sessionAvBand = histogram bandRange . ((fractionalHours . availableTime) `vs` band)

> periodEfficiencyByBand :: [Period] -> [Float] -> [(Band, Float)]
> periodEfficiencyByBand ps es = 
>     histogram bandRange . (effSchdMins `vs` (band . session . fst)) $ zip ps es
>   where 
>     effSchdMins (p, e) = e * (fractionalHours . duration $ p)

> decVsElevation :: [Period] -> [(Float, Radians)]
> decVsElevation ps = (dec . session) `vs` elevationFromZenith $ ps 

> --etaFn :: [(Frequency, Float)]
> --etaFn = [(f, minObservingEff f) | f <- [2.0 .. 60.0]]

> efficiencyVsFrequency :: [Session] -> [Float] -> [(Float, Float)]
> efficiencyVsFrequency sessions =
>     (snd `vs` (frequency . fst)) . zip sessions

> historicalFreq :: [Period] -> [Float]
> historicalFreq = map (frequency . session)

> historicalDec :: [Period] -> [Radians]
> historicalDec = map (dec . session)

> historicalRA :: [Period] -> [Radians]
> historicalRA = map (ra . session)

> historicalTime :: [Period] -> [DateTime]
> historicalTime = map startTime
>
> historicalTime' :: [Period] -> [Int]
> historicalTime' ps = map (minutesToDays . flip diffMinutes' tzero) times
>   where
>     times = sort . map startTime $ ps
>     tzero = head times

> minutesToDays  min = min `div` (24 * 60)
> fractionalDays min = fromIntegral min / (24.0 * 60.0)

> historicalExactTime' :: [Period] -> Maybe DateTime -> [Float]
> historicalExactTime' ps start = map (fractionalDays . flip diffMinutes' tzero) times
>   where
>     times = sort . map startTime $ ps
>     tzero = fromMaybe (head times) start

> historicalTime'' :: [DateTime] -> [Int]
> historicalTime'' dts = map (minutesToDays . flip diffMinutes' tzero) times
>   where
>     times = sort dts 
>     tzero = head times

> historicalExactTime'' :: [DateTime] -> Maybe DateTime -> [Float]
> historicalExactTime'' dts start = map (fractionalDays . flip diffMinutes' tzero) times
>   where
>     times = sort dts 
>     tzero = fromMaybe (head times) start

> historicalLST    :: [Period] -> [Float]
> historicalLST ps = [utc2lstHours . addMinutes' (duration p `div` 2) . startTime $ p | p <- ps]

Produces a tuple of (satisfaction ratio, sigma) for each frequency bin scheduled.

> killBad n | isNaN n      = 0.0 -- Is this is right value to return?
>           | isInfinite n = 1.0 -- Is this is right value to return?
>           | otherwise    = n

> satisfactionRatio :: [Session] -> [Period] -> [(Float, Float, Float)]
> --satisfactionRatio ss ps = zip3 [1.0..50.0] sRatios sigmas
> satisfactionRatio ss ps = zip3 freqs sRatios sigmas
>   where 
>     pMinutes   = map (fromIntegral . snd) (periodFreq ps) 
>     sMinutes   = map (fromIntegral . snd) (sessionFreq ss)
>     totalRatio = ratio pMinutes sMinutes
>     sRatios    = [killBad (x / y / totalRatio) | (x, y) <- zip pMinutes sMinutes]
>     sigmas     = [killBad (sqrt (x / y)) | (x, y) <- zip sRatios sMinutes]
>     freqs      = freqRange

> totalHrs      :: [Session] -> (Session -> Bool) -> Float
> totalHrs ss f = fractionalHours . sum $ [sAllottedT s | s <- ss, f s]

> totalPeriodHrs      :: [Period] -> (Period -> Bool) -> Float
> totalPeriodHrs ps f = fractionalHours . sum $ [duration p | p <- ps, f p]

> isInSemester :: Session -> String -> Bool
> isInSemester s sem = (semester . project $ s) == sem

> isPeriodInSemester :: Period -> String -> Bool
> isPeriodInSemester p sem = (dt2semester . startTime $ p) == sem

> isPeriodFromSemester :: Period -> String -> Bool
> isPeriodFromSemester p sem = (semester . project . session $ p) == sem

This function retrieves the history of pressures written in the trace, 
and returns them, for each band as [(day #, pressure)].

> bandPressuresByTime :: [Trace] -> [[(Float, Float)]]
> bandPressuresByTime trace = --[zip (replicate 3 1.0) (replicate 3 2.0)]
>     map bandData bandRange 
>   where
>     bandData band = [(fromIntegral x, y) | (x, y) <- zip days (getBandData band)]
>     fp    = getFreqPressureHistory trace -- [(array (L,W) [(L,9.850087), ..]]
>     times = getTimestampHistory trace
>     days  = historicalTime'' [getTimestamp t | t <- times]
>     getBandData band = getBandPressures band fp
>     

> getBandPressures :: Band -> [Trace] -> [Float]
> getBandPressures band bp = map (getBandPressure band) bp 
>   where
>     getBandPressure band t = getFreqPressure t ! band

This function retrieves the history of pressure bins written in the trace, 
and returns them, for each band as [(day #, (n, d))].
Here n and d are used for calculating the pressure: 1 + log (n/d)
We sometimes refer to n as 'remaining' and d as 'past'.

> bandPressureBinsByTime :: [Trace] -> [[(Float, (Int, Int))]]
> bandPressureBinsByTime trace = --[zip (replicate 3 1.0) (replicate 3 2.0)]
>     map bandData bandRange
>   where
>     bandData band = [(fromIntegral x, y) | (x, y) <- zip days (getBandData band)]
>     fp    = getFreqPressureBinHistory trace -- [(array (L,W) [(L,9.850087), ..]]
>     times = getTimestampHistory trace
>     days  = historicalTime'' [getTimestamp t | t <- times]
>     getBandData band = getBandPressureBins band fp
>     

> getBandPressureBins :: Band -> [Trace] -> [(Int, Int)]
> getBandPressureBins band bp = map (getBandPressureBin band) bp 
>   where
>     getBandPressureBin band t = getFreqPressureBin t ! band

> raPressuresByTime :: [Trace] -> [[(Float, Float)]]
> raPressuresByTime trace = 
>     map (raData . round) raRange
>   where
>     raData ra = [(fromIntegral x, y) | (x, y) <- zip days (getRaData ra)]
>     rap   = getRaPressureHistory trace
>     times = getTimestampHistory trace
>     days  = historicalTime'' [getTimestamp t | t <- times]
>     getRaData ra = getRaPressures ra rap

> getRaPressures    :: Int -> [Trace] -> [Float]
> getRaPressures ra = map $ \t -> getRaPressure t ! ra

The originally scheduled periods can be reconstructed from the observed
periods, and those that were canceled: put every canceled period in its
original slot (this will be overwritting a backup period, or a blank).

> getOriginalSchedule :: [Period] -> [Trace] -> [Period]
> getOriginalSchedule observed trace = sort $ originals observed ++ canceled
>   where 
>     canceled = getCanceledPeriods trace
>     originals ps = [p | p <- ps, not . pBackup $ p]

> getOriginalSchedule' :: [Period] -> [Period] -> [Period]
> getOriginalSchedule' observed canceled = sort $ originals observed ++ canceled
>   where 
>     originals ps = [p | p <- ps, not . pBackup $ p]

> getScheduledDeadTime :: DateTime -> Minutes -> [Period] -> [Trace] -> [(DateTime, Minutes)]
> getScheduledDeadTime start dur observed = findScheduleGaps start dur . getOriginalSchedule observed

> getScheduledDeadTimeHrs :: DateTime -> Minutes -> [Period] -> [Trace] -> Float
> getScheduledDeadTimeHrs start dur obs = fractionalHours . sum . map (\dt -> snd dt) . getScheduledDeadTime start dur obs

> findScheduleGaps :: DateTime -> Minutes -> [Period] -> [(DateTime, Minutes)]
> findScheduleGaps start dur ps = findScheduleGaps' $
>     begin : [(startTime p, duration p) | p <- ps] ++ [end]
>   where
>     begin = (start, 0)
>     end   = (dur `addMinutes'` start, 0)

> findScheduleGaps' ps = [(d1 `addMinutes'` s1, gap) |
>     ((s1,d1), (s2,d2)) <- zip ps (tail ps), gap <- [(s2 `diffMinutes'` s1) - d1], gap > 0]

> getTotalHours :: [Period] -> Float
> getTotalHours = fractionalHours . sum . map duration

> totalSessionHrs :: [Session] -> Float
> totalSessionHrs = fractionalHours . sum . map sAllottedT

If you were scheduling with the scheduleMinDuration strategy, how much
time could you really schedule with these sessions?

> totalSessMinDurHrs :: [Session] -> Float
> totalSessMinDurHrs = fractionalHours . sum . map availableTime

> availableTime s
>     | minDuration s == 0 = 0
>     | otherwise          = minDuration s * (sAllottedT s `div` minDuration s)

> crossCheckSimulationBreakdown :: Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> String
> crossCheckSimulationBreakdown simulated scheduled observed canceled obsBackup totalDead schedDead failedBackup =
>     concat warnings ++ "\n"
>   where
>     error = "WARNING: "
>     w1 = if totalDead /= schedDead + failedBackup then error ++ "Total Dead Time != Scheduled Dead Time + Failed Backup Time!" else ""
>     -- this warning is no longer applicable, since each simulation stip
>     -- calls dailySchedule, which schedule's more then the 'simulated' time
>     w2 = "" -- if observed + totalDead /= simulated then error ++ "Total Simulated Time != Observed + Dead Times!\n" else ""
>     w3 = if scheduled - observed /= canceled - obsBackup then error ++ "Scheduled - Observed Time != Canceled - Observed Backup Times!\n" else ""
>     warnings = [w1, w2, w3]

> breakdownSimulationTimes :: [Session] -> DateTime -> Minutes -> [Period] -> [Period] -> (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float)
> breakdownSimulationTimes sessions start dur observed canceled = 
>     ( fractionalHours dur                            -- simHrs
>     , totalSessionHrs sessions                       -- sessHrs
>     , totalSessionHrs . filter backup $ sessions     -- sessBackupHrs
>     , totalSessMinDurHrs sessions                    -- sessAvHrs
>     , totalSessMinDurHrs . filter backup $ sessions  -- sessAvBackupHrs
>     , getTotalHours originalSchedule                 -- scheduledHrs
>     , getTotalHours observed                         -- observedHrs
>     , canceledHrs
>     , obsBackupHrs
>     , fractionalHours . sum $ map snd observedGaps   -- totalObsDeadHrs
>     , fractionalHours . sum $ map snd scheduledGaps  -- totalSchDeadHrs
>     , canceledHrs - obsBackupHrs                     -- failedBackupHrs
>     )
>   where
>     originalSchedule = getOriginalSchedule' observed canceled
>     canceledHrs      = getTotalHours canceled
>     obsBackupHrs     = getTotalHours . filter pBackup $ observed
>     observedGaps     = findScheduleGaps start dur observed
>     scheduledGaps    = findScheduleGaps start dur originalSchedule

> scheduleHonorsFixed :: [Period] -> [Period] -> Bool
> scheduleHonorsFixed [] _ = True
> scheduleHonorsFixed fixed schedule =  dropWhile (==True) (findFixed fixed schedule) == []
>   where
>     findFixed fs schedule = [isJust (find (==f) schedule) | f <- fs]

Read Y versus X as you would expect with normal plotting nomenclature.
Produces list of (x, y) coordinate pairs.

> vs       :: (a -> b) -> (a -> c) -> [a] -> [(c, b)]
> y `vs` x = map $ x &&& y

> count :: (Ord a, Ord b, Num b) => (t -> a) -> [a] -> [t] -> [(a, b)]
> count f buckets = histogram buckets . (const 1 `vs` f)

> histogram :: (Ord a, Ord b, Num b) => [a] -> [(a, b)] -> [(a, b)]
> histogram buckets xys = [(x, sum ys) | (x, ys) <- allocate buckets xys]

> allocate buckets = allocate' buckets . sort
          
> allocate'            :: (Ord a, Ord b, Num b) => [a] -> [(a, b)] -> [(a, [b])]
> allocate' []     _   = []
> allocate' (b:bs) xys = (b, map snd within) : allocate' bs without
>   where
>     (within, without) = span (\(x, _) -> x <= b) xys

> meanFreqsByBin       :: [Float] -> [Float]
> meanFreqsByBin freqs = mean frequencyBins [(x, x) | x <- freqs]

> medianByBin :: [(Float, Float)] -> [Float]
> medianByBin  = median frequencyBins

> meanByBin :: [(Float, Float)] -> [Float]
> meanByBin  = mean frequencyBins

> stddevByBin :: [(Float, Float)] -> [Float]
> stddevByBin  = stddev frequencyBins

> sdomByBin :: [(Float, Float)] -> [Float]
> sdomByBin  = sdom frequencyBins


> mean, median, stddev, sdom   :: [Float] -> [(Float, Float)] -> [Float]
> [mean, median, stddev, sdom] = map simpleStat [mean', median', stddev', sdom']

simpleStat provides a way to perform statistics on binned data

> simpleStat f buckets = map (f . snd) . allocate buckets

histStat provides a way to perform statistics on historgram data
f is a function like mean', etc.

> histStat :: ([Float] -> Float) -> [(Float, Float)] -> Float
> histStat f histData = f newData
>   where
>     newData = concat $ map (\x -> replicate (round . snd $ x) (fst x)) histData

> mean' xs = sum xs / (fromIntegral . length $ xs)

> median' xs = sort xs !! (length xs `div` 2)

> stddev' xs = sqrt $ sum [(x - m) ^ 2 | x <- xs] / (fromIntegral . length $ xs)
>   where
>     m = mean' xs

> sdom' xs = stddev' xs / (sqrt . fromIntegral . length $ xs)

> ratio :: [Float] -> [Float] -> Float
> ratio = (/) `on` sum

> frequencyBins :: [Float]
> frequencyBins =
>     [0.0, 2.0, 3.95, 5.85, 10.0, 15.4, 20.0, 24.0, 26.0, 30.0, 35.0, 40.0, 45.0, 50.0, 80.0, 85.0, 90.0, 95.0, 100.0, 105.0, 110.0, 115.0, 120.0]

> promote   :: ([Session] -> t) -> [Period] -> t
> promote f = f . map session
