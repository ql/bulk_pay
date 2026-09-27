# db pool size is read from the same MAX_THREADS (see config/database.yml), so they can't drift apart
max_threads = Integer(ENV.fetch('MAX_THREADS', 5))
threads max_threads, max_threads

# every worker has its own pool: instances * workers * threads must stay below postgres max_connections
workers Integer(ENV.fetch('WEB_CONCURRENCY', 0))

port Integer(ENV.fetch('PORT', 9292))
