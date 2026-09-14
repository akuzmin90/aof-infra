import com.hitmakers.jenkins.BackendConsoleFactory;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
public class ConsoleFilterTest {
 public static void main(String[] args) throws Exception {
  ByteArrayOutputStream bytes = new ByteArrayOutputStream();
  var filter = new BackendConsoleFactory.Condensed(bytes);
  String input = "[PodInfo] jenkins/worker-1\n\tPod [Pending][Unschedulable] no eligible node\n";
  for(int i=0;i<20;i++) filter.write(input.getBytes(StandardCharsets.UTF_8));
  filter.write("\tContainer [helm] waiting [ContainerCreating] No message\n > git fetch secretless-repo\nChecking out Revision abc\nERROR: registry unavailable\nПривет\n".getBytes(StandardCharsets.UTF_8));
  filter.close();
  String out=bytes.toString(StandardCharsets.UTF_8);
  if(out.split("no eligible node",-1).length!=2 || out.contains("PodInfo") || out.contains("git fetch") || !out.contains("Checking out Revision abc") || !out.contains("ERROR: registry unavailable") || !out.contains("Привет")) throw new AssertionError(out);
  System.out.println("PASS console filter: deduplication, milestones, errors and UTF-8 preserved");
 }
}
