;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; Description
;;; Author         Michael Kappert 2018
;;; Last Modified <michael 2019-04-02 00:22:41>

(in-package :virtualhelm)

#|
(check-window 12 168
              :increment 180
              :start cl-geomath::+los-angeles+
              :dest cl-geomath::+honolulu+
              :stepmax (* 60 60 24 5)
              :polars "maxi_trimaran")
|#

(defun check-window (start-offset
                     window-size
                     &key
                       (logfile "startwindow.log")
                       (increment 60)
                       (start +marseille+)
                       (dest +carthago+)
                       (stepmax (* 60 60 24 6))
                       (polars "maxi_trimaran_x10percent")
                       (options  '("winch" "reach" "foil" "heavy" "light" "hull")))
  (let*
      ((first (adjust-timestamp (now) (:offset :hour start-offset)))
       (last (adjust-timestamp first (:offset :hour window-size))))
    (adjust-timestamp! first (:set :minute 0) (:set :sec 0))
    (adjust-timestamp! last (:set :minute 0) (:set :sec 0))
    (with-open-file (f logfile
                       :direction :output
                       :if-exists :append
                       :if-does-not-exist :create)
      (do ((starttime first
                      (adjust-timestamp starttime (:offset :minute increment)))
           (result (list)))
          ((timestamp> starttime last)
           result)
        (let ((parameters
               (make-routing :start start
                             :dest dest
                             :stepmax stepmax
                             :polars polars
                             :options options
                             :starttime starttime)))
          (multiple-value-bind (route error)
              (ignore-errors
                (get-route parameters))
            (cond
              (route
               (push (routeinfo-stats route) result)
               (format f "~a~%" (routeinfo-stats route)))
              (t
               (format f "Error: ~a, parameters were ~a ~%" error parameters)))))))))


;;; EOF
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
