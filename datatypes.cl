;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Description
;;; Author         Michael Kappert 2017
;;; Last Modified <michael 2021-03-31 23:57:52>

(in-package :virtualhelm)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; A routing stores the start and destination of the route
;;; and other routing parameters.
        
(defstruct routing
  (dataset 'noaa-dataset)
  (race-id "440.1")
  (polars 4)
  (limits "limits.json")
  (starttime nil) ;; NIL or "yyyy-MM-ddThh:mm" (datetime-local format)
  (starttimezone "+00:00") ;; NIL or "yyyy-MM-ddThh:mm" (datetime-local format)
  (cycle nil) ;; NIL = latest available
  (options '("reach"))
  (minwind t) ;; m/s !!
  (start +LESSABLES+) ;; set-paramater needs a valid initial values
  (dest +NEW-YORK+)   ;; because start/dest lat and lon are set separately.
  (mode +max-origin+)
  (fan 90)            ;; FIXME: Larger value yields narrower search, increases time. Looks like a bug.
  (stepmax +12h+ :type fixnum))

(defmethod print-object ((thing routing) stream)
  (format stream "{T=~a C=~a O=~a}"
          (routing-starttime thing)
          (routing-cycle thing)
          (routing-options thing)))


(defstruct duration days hours minutes seconds)
(defmethod print-object ((thing duration) stream)
  (format stream "~dd ~2,'0dh ~2,'0dm"
          (duration-days thing)
          (duration-hours thing)
          (duration-minutes thing)))

(defun routing-foils (routing)
  (member "foil" (routing-options routing) :test #'string=))
(defun routing-hull (routing)
  (member "hull" (routing-options routing) :test #'string=))
(defun routing-winches (routing)
  (member "winch" (routing-options routing) :test #'string=))

(defstruct routeinfo best polars maxspeed stats tracks isochrones)

(defmethod print-object ((thing routeinfo) stream)
  (let ((stats (or (routeinfo-stats thing)
                   (make-routestats))))
    (format stream "#<RouteInfo Start ~a Duration ~a Isochrones ~a>"
            (routestats-start stats)
            (routestats-duration stats)
            (length (routeinfo-isochrones thing)))))

(defstruct routestats start duration sails min-wind max-wind min-twa max-twa)
(defmethod print-object ((thing routestats) stream)
  (format stream "~a | ~a | ~2,'0d - ~2,'0d | ~{~a~^, ~}"
          (format-datetime nil (routestats-start thing))
          (routestats-duration thing)
          (routestats-min-wind thing)
          (routestats-max-wind thing)
          (routestats-sails thing)))

(defstruct isochrone center time offset params path)

(defstruct twainfo twa heading twapath hdgpath)

(defmethod print-object ((thing twainfo) stream)
  (format stream "{TWA:~a Heading:~a}"
          (twainfo-twa thing)
          (twainfo-heading thing)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Isochrones are described by sets of routepoints.
;;;
;;; ### Think of a good sorting/data structure to support finding the most advanced point in a sector

(defstruct (routepoint
             (:constructor create-routepoint (predecessor position time heading &optional destination-distance speed sail penalty wind-dir wind-speed (origin-angle 0) (origin-distance 0))))
  predecessor position time heading destination-distance speed sail penalty wind-dir wind-speed origin-angle origin-distance)

(defstruct trackpoint
  time position heading dtf speed sail penalty twd tws twa)

(defun create-trackpoint (routepoint successor)
  (make-trackpoint :time (routepoint-time routepoint)
                   :position (routepoint-position routepoint)
                   :heading (routepoint-heading successor)
                   :dtf (routepoint-destination-distance routepoint)
                   :speed (routepoint-speed routepoint)
                   :sail (routepoint-sail successor)
                   :twd (routepoint-wind-dir routepoint)
                   :tws (routepoint-wind-speed routepoint)
                   :twa (routepoint-twa successor)
                   :penalty (routepoint-penalty successor)))

(defun routepoint-twa (rp)
  (when (and (routepoint-heading rp)
             (routepoint-wind-dir rp))
    (round (heading-twa (routepoint-wind-dir rp)
                        (routepoint-heading rp)))))

(defmethod print-object ((thing routepoint) stream)
  (format stream " ~a@~a"
          (routepoint-position thing)
          (routepoint-time thing)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Time

(defun format-timespec-datehh (stream timestamp &key (timezone +utc-zone+) (offset 0))
  "Format timestamp as YYYY-MM-DD, HH Uhr"
  (format-timestring stream
                     (adjust-timestamp timestamp (offset :hour offset))
                     :format '((:year 4) "-" (:month 2) "-" (:day 2) ", " (:hour 2) "Uhr") :timezone timezone))  

(defun format-time (stream timestamp)
  (format stream "~2,'0d:~2,'0dZ"
          (timestamp-hour timestamp :timezone +utc-zone+)
          (timestamp-minute timestamp :timezone +utc-zone+)))

(defun format-date (stream timestamp)
  (format stream "~4,'0d-~2,'0d-~2,'0d"
          (timestamp-year timestamp :timezone +utc-zone+)
          (timestamp-month timestamp :timezone +utc-zone+)
          (timestamp-day timestamp :timezone +utc-zone+)))

(defun format-datetime (stream timestamp &key (timezone +utc-zone+))
  (format stream "~4,'0d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0dZ"
          (timestamp-year timestamp :timezone timezone)
          (timestamp-month timestamp :timezone timezone)
          (timestamp-day timestamp :timezone timezone)
          (timestamp-hour timestamp :timezone timezone)
          (timestamp-minute timestamp :timezone timezone)
          (timestamp-second timestamp :timezone timezone)))

(defun parse-datetime (string)
  (destructuring-bind (date time)
      (cl-utilities:split-sequence #\T string)
    (destructuring-bind (y m d)
        (cl-utilities:split-sequence #\- date)
      (destructuring-bind (utime &optional (tz ""))
          (cl-utilities:split-sequence #\Z time)
        (destructuring-bind (hr min &optional (sec "0"))
            (cl-utilities:split-sequence #\: utime)
          (assert (equal tz ""))
          (encode-timestamp 0
                            (read-from-string sec)
                            (read-from-string min)
                            (read-from-string hr)
                            (read-from-string d)
                            (read-from-string m)
                            (read-from-string y)
                            :timezone +utc-zone+))))))

(defmethod print-object ((thing timestamp) stream)
  (format-rfc1123-timestring stream thing))


;;; EOF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
