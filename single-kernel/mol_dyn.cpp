#include "common.h"
#include <iostream>

//using namespace cl::sycl;
namespace s = cl::sycl;
class MolecularDynamicsKernel;

class MolecularDynamicsBench
{
protected:    
    std::vector<s::float4> input;
    std::vector<s::float4> output;
    std::vector<int> neighbour;
	int neighCount;
	int cutsq;
	int lj1;
	int lj2;
	int inum;
    BenchmarkArgs args;

public:
  MolecularDynamicsBench(const BenchmarkArgs &_args) : args(_args) {}
  
  void setup() {      
    // host memory allocation and initialization
	neighCount = 15;
	cutsq = 50;
	lj1 = 20;
	lj2 = 0.003f;
	inum = 0;
    
    input.resize(args.problem_size*sizeof(s::float4));
    neighbour.resize(args.problem_size);
    output.resize(args.problem_size*sizeof(s::float4));

    for (size_t i = 0; i < args.problem_size; i++) {
        input[i] = s::float4{(float)i,(float)i,(float)i,(float)i}; // Same value for all 4 elements. Could be changed if needed
    }
    for (size_t i = 0; i < args.problem_size; i++) {
        neighbour[i] = i+1;
    }
  }

  void run() {    
    s::buffer<s::float4, 1> input_buf(input.data(), s::range<1>(args.problem_size*sizeof(s::float4)));
    s::buffer<int, 1> neighbour_buf(neighbour.data(), s::range<1>(args.problem_size));
    s::buffer<s::float4, 1> output_buf(output.data(), s::range<1>(args.problem_size*sizeof(s::float4)));
    
    args.device_queue.submit(
        [&](cl::sycl::handler& cgh) {
      auto in = input_buf.get_access<s::access::mode::read>(cgh);
      auto neigh = neighbour_buf.get_access<s::access::mode::read>(cgh);
      auto out = output_buf.get_access<s::access::mode::discard_write>(cgh);

      cl::sycl::range<1> ndrange (args.problem_size);

      cgh.parallel_for<class MolecularDynamicsKernel>(ndrange,
        [=](cl::sycl::id<1> idx) 
        {
            size_t gid= idx[0];

            if (gid < args.problem_size) {
                s::float4 ipos = in[gid];
                s::float4 f = {0.0f, 0.0f, 0.0f, 0.0f};
                int j = 0;
                while (j < neighCount) {
                    int jidx = neigh[j*inum + gid];
                    s::float4 jpos = in[jidx];

                    // Calculate distance
                    float delx = ipos.x() - jpos.x();
                    float dely = ipos.y() - jpos.y();
                    float delz = ipos.z() - jpos.z();
                    float r2inv = delx*delx + dely*dely + delz*delz;

                    // If distance is less than cutoff, calculate force
                    if (r2inv < cutsq) {
                        r2inv = 10.0f/r2inv;
                        float r6inv = r2inv * r2inv * r2inv;
                        float forceC = r2inv*r6inv*(lj1*r6inv - lj2);

                        f.x() += delx * forceC;
                        f.y() += dely * forceC;
                        f.z() += delz * forceC;
                    }
                    j++;
                }
                output[gid] = f;
            }
        });
    });
  }

  bool verify(VerificationSetting &ver) { 
    bool pass = true;
    unsigned equal = 1;
    const float tolerance = 0.00001;
    for(unsigned int i = 0; i < args.problem_size; ++i) {
        s::float4 ipos = input[i];
        s::float4 f = {0.0f, 0.0f, 0.0f, 0.0f};
        int j = 0;
        while (j < neighCount) {
            int jidx = neighbour[j*inum + i];
            s::float4 jpos = input[jidx];

            // Calculate distance
            float delx = ipos.x() - jpos.x();
            float dely = ipos.y() - jpos.y();
            float delz = ipos.z() - jpos.z();
            float r2inv = delx*delx + dely*dely + delz*delz;

            // If distance is less than cutoff, calculate force
            if (r2inv < cutsq) {
                r2inv = 10.0f/r2inv;
                float r6inv = r2inv * r2inv * r2inv;
                float forceC = r2inv*r6inv*(lj1*r6inv - lj2);

                f.x() += delx * forceC;
                f.y() += dely * forceC;
                f.z() += delz * forceC;
            }
            j++;
        }

        if (fabs(f.x()-output[i].x()) > tolerance || fabs(f.y()-output[i].y()) > tolerance || fabs(f.z()-output[i].z()) > tolerance) {
            pass = false;
            break;
        }
    }
    return pass;
  }
  
  static std::string getBenchmarkName() {
    return "MolecularDynamics";
  }
};

int main(int argc, char** argv)
{
  BenchmarkApp app(argc, argv);
  app.run<MolecularDynamicsBench>();  
  return 0;
}
