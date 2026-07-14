(defpackage #:ninja
  (:use #:common-lisp)
  (:documentation "Ninja writing interface along with utility streams for build files.")
  (:export #:escape
           #:*line-end*
           #:*line-start*
           #:*line-width*
           #:make-line-wrapping-stream
           #:write-bindings
           #:write-build
           #:write-comment
           #:write-default
           #:write-include
           #:write-pool
           #:write-rule))
