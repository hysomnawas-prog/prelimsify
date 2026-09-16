-- Prelimsify: automatically preserve Mocktest categories.
-- Safe to run more than once.

ALTER TABLE public.quiz_projects
  ADD COLUMN IF NOT EXISTS topic text;

-- Recover categories that were previously stored inside paper.topic.
UPDATE public.quiz_projects
SET topic = NULLIF(paper->>'topic', '')
WHERE (topic IS NULL OR topic = '')
  AND paper ? 'topic'
  AND NULLIF(paper->>'topic', '') IS NOT NULL;

-- Keep the topic column indexed for fast loading/grouping.
CREATE INDEX IF NOT EXISTS quiz_projects_topic_idx
  ON public.quiz_projects(topic);

-- Future writes: if paper.topic is supplied, keep the column synchronized.
CREATE OR REPLACE FUNCTION public.sync_quiz_project_topic()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.paper ? 'topic' THEN
    NEW.topic := NULLIF(NEW.paper->>'topic', '');
  ELSIF NEW.topic IS NOT NULL THEN
    NEW.paper := jsonb_set(COALESCE(NEW.paper, '{}'::jsonb), '{topic}', to_jsonb(NEW.topic), true);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS quiz_projects_sync_topic ON public.quiz_projects;
CREATE TRIGGER quiz_projects_sync_topic
BEFORE INSERT OR UPDATE OF paper, topic ON public.quiz_projects
FOR EACH ROW
EXECUTE FUNCTION public.sync_quiz_project_topic();

-- Ensure authenticated users can update their own rows; admin access is
-- still governed by the existing admin policy if present.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.quiz_projects TO authenticated;
