> module Antioch.DateTime where

> import Antioch.SunRiseSet
> import Data.Fixed                 (div')
> import Data.Function              (on)
> import Data.Time.Calendar hiding  (fromGregorian, toGregorian)
> import Data.Time.Clock hiding     (getCurrentTime)
> import Data.Time.Format
> import Data.Time.LocalTime
> import Database.HDBC
> import Numeric                    (fromRat)
> import System.Locale
> import System.Time hiding         (toClockTime)
> import Test.QuickCheck
> import Text.Printf

> import qualified Data.Time.Calendar as Calendar
> import qualified Data.Time.Clock as Clock

> type DateTime = Int

> -- edt <- getCurrentTimeZone     -- if running in Green Bank then EDT

> instance Arbitrary UTCTime where
>     arbitrary       = do
>         offset <- choose (0, 20000) :: Gen Float
>         return . fromMJD' $ offset + fromRational startOfTimeMJD
>     coarbitrary _ b = b

So that we can use our UTCTime class with HDBC.

> -- instance SqlType UTCTime where
> --     toSql   = toSql . toClockTime
> --     fromSql = fromClockTime . fromSql

Defined here so that users don't need to know about Data.Time.Clock.

> getCurrentTime :: IO DateTime
> getCurrentTime = fmap toSeconds Clock.getCurrentTime

> secondsToMJD   :: Int -> Float
> secondsToMJD s = 40587.0 + (fromIntegral s / 86400.0)

> secondsToMJD'   :: Int -> Double
> secondsToMJD' s = 40587.0 + (fromIntegral s / 86400.0)

> prop_secondsToMJD = invariant $ fromMJD' . secondsToMJD . toSeconds

Conversion back and forth between UTCTime and MJD.

> toMJD :: UTCTime -> Rational
> toMJD = getModJulianDate . toUniversalTime

> toMJD' :: RealFloat a => UTCTime -> a
> toMJD' = fromRat . toMJD

> fromMJD :: Rational -> UTCTime
> fromMJD = fromUniversalTime . ModJulianDate

> fromMJD' :: RealFloat a => a -> UTCTime
> fromMJD' = fromMJD . realToFrac

> invariant f x = f x == x
  
> prop_MJD  = invariant $ fromMJD  . toMJD
> prop_MJD' = invariant $ fromMJD' . toMJD'

Because UTCTime is opaque, we need to convert to UniversalTime in
order to do anything with it, but these functions are mainly of
interest internally.

> toUniversalTime :: UTCTime -> UniversalTime
> toUniversalTime = localTimeToUT1 0 . utcToLocalTime utc

> fromUniversalTime :: UniversalTime -> UTCTime
> fromUniversalTime = localTimeToUTC utc . ut1ToLocalTime 0

> prop_Universal = invariant $ fromUniversalTime . toUniversalTime

> replaceYear :: Int -> DateTime -> DateTime
> replaceYear yyyy dt = fromGregorian yyyy m d h mm s
>    where
>      (_, m, d, h, mm, s) = toGregorian dt

> replaceMonth :: Int -> DateTime -> DateTime
> replaceMonth month dt = fromGregorian y month d h mm s
>    where
>      (y, _, d, h, mm, s) = toGregorian dt

> setHour :: Int -> DateTime -> DateTime
> setHour hour dt = fromGregorian y m d hour 0 0
>   where
>      (y, m, d, _, _, _) = toGregorian dt
   
Takes into account 12 months a year and wrap-around

> addMonth :: DateTime -> DateTime
> addMonth dt | month == 12 = replaceYear nextYear $ replaceMonth 1 dt
>             | otherwise   = replaceMonth nextMonth dt
>   where
>      (y, month, d, h, mm, s) = toGregorian dt
>      nextMonth = month + 1
>      nextYear = y + 1

Take apart a UTCTime into pieces and parts.
  
> toGregorian'    :: DateTime -> (Int, Int, Int)
> toGregorian' dt = (y, m, d)
>   where
>     (y, m, d, _, _, _) = toGregorian dt

> toGregorian    :: DateTime -> (Int, Int, Int, Int, Int, Int)
> toGregorian dt = (fromIntegral year, month, day', hours, minutes, seconds `div'` 1)
>   where
>     LocalTime day tod   = utcToLocalTime utc . fromSeconds $ dt
>     (year, month, day') = Calendar.toGregorian day
>     TimeOfDay hours minutes seconds = tod

Combine pieces and parts to produce a UTCTime.
      
> fromGregorian'       :: Int -> Int -> Int -> DateTime
> fromGregorian' y m d = fromGregorian y m d 0 0 0

> fromGregorian :: Int -> Int -> Int -> Int -> Int -> Int -> DateTime
> fromGregorian year month day hours minutes seconds = toSeconds $
>     UTCTime day' (secondsToDiffTime . fromIntegral $ seconds')
>   where
>     day'     = Calendar.fromGregorian (fromIntegral year) month day
>     seconds' = 3600 * hours + 60 * minutes + seconds

> roundToHour dt = 3600 * ((dt + 1800) `div` 3600)

Getting closer to the machine: Not all the functionality of
System.Time is available in Data.Time, and the only way we can convert
back and forth is to go through seconds.

> toSeconds    :: UTCTime -> Int
> toSeconds dt = floor $
>     86400.0 * fromRational (toMJD dt - startOfTimeMJD)

> fromSeconds   :: Int -> UTCTime
> fromSeconds s = fromMJD $
>     fromIntegral s / 86400 + startOfTimeMJD

> toClockTime    :: UTCTime -> ClockTime
> toClockTime dt = TOD (fromIntegral . toSeconds $ dt) 0

> fromClockTime           :: ClockTime -> UTCTime
> fromClockTime (TOD s _) = fromSeconds . fromIntegral $ s

> startOfTime :: DateTime
> startOfTime = 0

> startOfTimeMJD :: Rational
> startOfTimeMJD = toMJD $ UTCTime (Calendar.fromGregorian 1970 1 1) 0

Formatting and parsing, with special attention to the format used by
ODBC and MySQL.

> toSqlString    :: DateTime -> String
> toSqlString dt = printf "%04d-%02d-%02d %02d:%02d:%02d" year month day hours minutes seconds
>   where
>     (year, month, day, hours, minutes, seconds) = toGregorian dt

> toHttpString    :: DateTime -> String
> toHttpString dt = formatUTCTime httpFormat . fromSeconds $ dt

> fromSqlString :: String -> Maybe DateTime
> fromSqlString = fmap toSeconds . parseUTCTime sqlFormat

> fromSqlDateString :: String -> Maybe DateTime
> fromSqlDateString = fmap toSeconds . parseUTCTime sqlDateFormat

> fromHttpString :: String -> Maybe DateTime
> fromHttpString = fmap toSeconds . parseUTCTime httpFormat

The string conversions may loss precision at the level of a second.  This is
close enough for our purposes (TBF)?

> prop_SqlString dt = diffSeconds dt dt' <= 1
>   where
>     Just dt' = fromSqlString . toSqlString $ dt

> prop_SqlStartOfTime _ = toSqlString startOfTime == "1970-01-01 00:00:00"

> formatUTCTime :: String -> UTCTime -> String
> formatUTCTime = formatTime defaultTimeLocale

> parseUTCTime :: String -> String -> Maybe UTCTime
> parseUTCTime = parseTime defaultTimeLocale

> formatLocalTime :: String -> LocalTime -> String
> formatLocalTime = formatTime defaultTimeLocale

> parseLocalTime :: String -> String -> Maybe LocalTime
> parseLocalTime = parseTime defaultTimeLocale

> sqlFormat = iso8601DateFormat (Just "%T")

> sqlDateFormat = iso8601DateFormat (Just "")

> httpFormat = iso8601DateFormat (Just " %HA%MA%S") -- TBF space needed?

Simple arithmetic.

> addHours :: Int -> DateTime -> DateTime
> addHours = addMinutes . (60 *)

> diffHours :: Int -> DateTime -> DateTime
> diffHours x = (`div` 60) . diffMinutes x

> addMinutes' :: Int -> DateTime -> DateTime
> addMinutes' = addMinutes
  
> addMinutes :: Int -> DateTime -> DateTime
> addMinutes = addSeconds . (60 *)

> diffMinutes' :: DateTime -> DateTime -> Int
> diffMinutes' = diffMinutes

> diffMinutes   :: DateTime -> DateTime -> Int
> diffMinutes x = (`div` 60) . diffSeconds x
  
> addSeconds :: Int -> DateTime -> DateTime
> addSeconds = (+)

> diffSeconds :: DateTime -> DateTime -> Int
> diffSeconds = (-)

These next two functions give back a datetime for when the sun
should rise or set for the given datetime.

> {-
> getRise    :: DateTime -> DateTime
> getRise dt = fromGregorian year month day hrRise minRise 0
>   where 
>     (year, month, day, _, _, _) = toGregorian dt
>     (hrRise, minRise) = fromHoursToHourMins . sunRise . toDayOfYear $ dt
> -}

> getRise :: DateTime -> (Int -> Float) -> DateTime
> getRise dt riseFnc = fromGregorian year month day hrRise minRise 0
>   where 
>     (year, month, day, _, _, _) = toGregorian dt
>     (hrRise, minRise) = fromHoursToHourMins . riseFnc . toDayOfYear $ dt

> {-
> getSet    :: DateTime -> DateTime
> getSet dt = fromGregorian year month day hrSet minSet 0
>   where 
>     (year, month, day, _, _, _) = toGregorian dt
>     (hrSet, minSet) = fromHoursToHourMins . sunSet . toDayOfYear $ dt
> -} 

TBF: set times, when using a function that offsets it, can wrap to the next dy

> getSet    :: DateTime -> (Int -> Float) -> DateTime
> getSet dt setFnc = fromGregorian year month day hrSet minSet 0
>   where 
>     setHrs = setFnc . toDayOfYear $ dt
>     (hrSet, minSet) = fromHoursToHourMins setHrs
>     -- If the setting time is less then the physical sun set time,
>     -- then it must have wrapped around
>     pySetHrs = sunRise . toDayOfYear $ dt
>     dayDt = if pySetHrs < setHrs then dt else ((24*60) `addMinutes'` dt)  
>     (year, month, day, _, _, _) = toGregorian dayDt


Definitions of Day/Night differ:
   * physical - when the actual sun sets and rises
   * PTCS versions - include offsets after sun set/rise

Physical Definition:

> isDayTime    :: DateTime -> Bool
> isDayTime dt = getRise dt sunRise <= dt && dt <= getSet dt sunSet

PTCS Version 1.0:

> isPTCSDayTime    :: DateTime -> Bool
> isPTCSDayTime dt = getRise dt ptcsSunRise <= dt && dt <= getSet dt ptcsSunSet

PTCS Version 2.0:

> isPTCSDayTime_V2    :: DateTime -> Bool
> isPTCSDayTime_V2 dt = getRise dt ptcsSunRise_V2 <= dt && dt <= getSet dt ptcsSunSet_V2

Calculates the day of the year by finding the difference in minutes
between the given datetime and the first of the year, and converting
this to integer days.

> toDayOfYear :: DateTime -> Int
> toDayOfYear dt = toDays $ dt `diffMinutes` yearStart
>   where
>     (year, _, _, _, _, _) = toGregorian dt
>     yearStart = fromGregorian (year) 1 1 0 0 0
>     toDays mins = (mins `div` (24*60)) + 1 --ceiling $ mins / (24*60)

Ex: 12.5 hours -> 12 hours and 30 minutes

> fromHoursToHourMins :: Float -> (Int, Int)
> fromHoursToHourMins hrs = (hr, mins)
>   where
>     hr = (floor hrs)::Int
>     mins = floor $ ((hrs - (fromIntegral hr)) * 60.0)

TBF use ET and translate to UT

> isHighRFITime :: DateTime -> Bool
> isHighRFITime dt = badRFIStart dt <= dt && dt <= badRFIEnd dt
>   where
>     badRFIStart dt = 86400 * (dt `div` 86400) + 12 * 3600  -- 8 AM ET
>     badRFIEnd dt   = 86400 * (dt `div` 86400) + 24 * 3600  -- 8 PM ET

