-- Tracks whether an offer (job_applications.status = 'offer') was accepted
-- or declined, so the Offer stat tile can show a tiny "N accepted / N
-- declined" sub-header. Nullable: most offers sit unanswered for a while,
-- and an application that has never reached 'offer' has nothing to answer.
alter table job_applications
  add column if not exists offer_response text
  check (offer_response is null or offer_response in ('accepted', 'declined'));
